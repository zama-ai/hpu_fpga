#!/usr/bin/env python
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This code tests the monomial multiplication coded in a "hardware style" against its definition.
# ==============================================================================================

from random import random
from random import seed
from collections import Counter
import sys  # manage errors
import math

# ==============================================================================
# Global variables
# ==============================================================================
N = 512  # Polynomial Degree
R = 8  # Radix of the NTT
PSI = 8  # Number of BUs instantiated in parallel
NTT_cps = R * PSI  # Coefficients per cycle consumed by the NTT

# Calculate number of sectors, each sector belongs to an input of a radix-R
# butterfly unit. A sector in this context is not to be confused with
# sectors in a RAM.
nr_of_sectors = R
# Calculate the columns per sector, this number equals the number of BUs PSI
# instantiated in parallel. A column (or "memory column") represents a dual-port
# memory. There are a total of NTT_cps = R * PSI dual-port memories spread over
# nr_of_sectors sectors.
cols_per_sector = PSI
# Calculate the number of rows of the memory, this number is derived from
# the number of elements N in the memory and the coefficients per clock cycle
# consumed by the NTT NTT_cps.
rows_per_sector = int(N / NTT_cps)

# ==============================================================================
# create_empty_mem
# ==============================================================================
def create_empty_mem():
    """
    Description:
      Function to create an empty memory.
      A memory is a 3 dimensional list that holds the N coefficients of
      the GLWE Polynomial.
      The N coefficients are divided over NTT_cps RAMs, each holding
      N/NTT_cps coefficients.
    Inputs:
    Outputs:
      mem_l: a 3D list representing an empty memory that can hold N coefficients.
    """
    # Fill the memory with zeros.
    mem_l = []
    for i in range(nr_of_sectors):
        sector_cols = []
        for j in range(cols_per_sector):
            sector_row = []
            for k in range(rows_per_sector):
                sector_row.append(0)
            sector_cols.append(sector_row)
        mem_l.append(sector_cols)

    return mem_l


# ==============================================================================
# print_mem
# ==============================================================================
def print_mem(mem_l):
    """
    Description:
      Function to orderly print the contents of a memory.
      A memory is a 3 dimensional list that holds the N coefficients of
      the GLWE Polynomial.
      This function prints the contents of the memory sector by sector and
      column by column.
    Inputs:
      mem_l: a 3D list representing a memory hold N coefficients.
    Outputs:
    TODO:
     - [ ] Update to print only a selected set of sectors.
    """
    print("")
    #  Iterate over Sectors
    for i in range(len(mem_l)):
        print("##### Memory Sector ", i, "#####")
        # Iterate over Rows
        for j in range(len(mem_l[i])):
            # Iterate over Columns
            for k in range(len(mem_l[i][j])):
                # 4 characters are chosen for debugging the case where
                # each memory location holds its index [0:N-1] and N=512.
                # In that case, the widest number to be printed is "-xyz".
                print("%4d" % mem_l[i][k][j], end=" ")
            print("")
        print("")


# ==============================================================================
# load_mem
# ==============================================================================
def load_mem(input_l, mem_l):
    """
    Description:
      Function to load a length-N input list input_l into the memory mem_l in
      the correct order.
    Inputs:
      input_l: The list of N inputs to be loaded in the memory.
      mem_l: The memory storing input_l.
    Outputs:
    """
    for sectors in range(nr_of_sectors):
        for cols in range(cols_per_sector):
            for rows in range(rows_per_sector):
                # Each sector contains cols_per_sector*rows_per_sector coefficients.
                # Each row contains cols_per_sector coefficients.
                mem_l[sectors][cols][rows] = input_l[
                    cols_per_sector * rows_per_sector * sectors
                    + cols_per_sector * rows
                    + cols
                ]


# ==============================================================================
# read_mem
# ==============================================================================
def read_mem(mem_l):
    """
    Description:
      Function to load/read a length-N list flattened_mem_l from
      the memory mem_l in the correct order.
    Inputs:
      mem_l: The memory holding the GLWE Polynomial.
    Outputs:
      flattened_mem_l: The list of N output to hold the content of the memory.
    """
    flattened_mem_l = [0 for i in range(N)]

    for sectors in range(nr_of_sectors):
        for cols in range(cols_per_sector):
            for rows in range(rows_per_sector):
                # Each sector contains cols_per_sector*rows_per_sector coefficients.
                # Each row contains cols_per_sector coefficients.
                flattened_mem_l[
                    cols_per_sector * rows_per_sector * sectors
                    + cols_per_sector * rows
                    + cols
                ] = mem_l[sectors][cols][rows]

    return flattened_mem_l


# ==============================================================================
# monomial_mult_definition
# ==============================================================================
def monomial_mult_definition(input_l, monomial_exponent, modulo):
    """
    Description:
      Function to perform the monomial multiplication on an input
      polynomial input_l, implemented using the definition of the operation.
    Inputs:
      input_l: Input list holding the polynomial to be multiplied.
      monomial_exponent: The exponent of the monomial, i.e. X^monomial_exponent.
      modulo: The value of the modulo.
    Outputs:
      output_l: The list of N outputs holding input_l * X^monomial_exponent.
    """
    # Copy the input polynomial to the output polynomial
    output_l = [input_l[i] for i in range(N)]

    # Multiply the output polynomial with 'X' monomial_exponent times.
    for i in range(monomial_exponent):
        output_l = output_l[-1:] + output_l[:-1]
        output_l[0] = -output_l[0] % modulo

    return output_l


# ==============================================================================
# check_access_conflicts
# ==============================================================================
def check_access_conflicts(access_ll):
    """
    Description:
      Function to check if 2d list of memory access indices contains conflicts.
      If no index occurs more than twice, no access conflicts are present in
      a dual-port memory.
      If access conflicts are present, the program will exit.
    Inputs:
      access_ll: A 2d list of memory accesses. Each element holds the indices for
      retrieving coefficient 1 and coefficient 2 of the on-the-fly monomial mult
      for that column of the memory.
    Outputs:
    """
    # Separate accesses for coefficients 1 and 2 into two lists
    access_coeff1 = []
    access_coeff2 = []
    for i in range(len(access_ll)):
        access_coeff1.append(access_ll[i][0])
        access_coeff2.append(access_ll[i][1])

    # For debugging
    # print(f"Checking Access List: {access_ll}")
    # print(f"Checking Access List for Coefficients 1: {access_coeff1}")
    # print(f"Checking Access List for Coefficients 2: {access_coeff2}")

    # Count the accesses per memory column for each coefficient
    access_frequency_coeff1 = Counter(access_coeff1)
    access_frequency_coeff2 = Counter(access_coeff2)

    # For debugging
    # print(f"Access frequencies coefficient 1: {access_frequency_coeff1}")
    # print(f"Access frequencies coefficient 2: {access_frequency_coeff2}")

    nr_of_access_conflicts = 0
    for i in range(NTT_cps):
        # Every column should be accessed exactly once per coefficient
        if (access_frequency_coeff1[i] == 1) and (access_frequency_coeff2[i] == 1):
            nr_of_access_conflicts += 0
        else:
            nr_of_access_conflicts += 1

    # Exit if access conflicts are present
    if nr_of_access_conflicts != 0:
        sys.exit("> ERROR: There are access conflicts")


# ==============================================================================
# monomial_mult_hw_on_the_fly
# ==============================================================================
def monomial_mult_hw_on_the_fly(src_mem, dst_mem, monomial_exponent, modulo):
    """
    Description:
      Function to perform the monomial multiplication on an input
      polynomial input_l, implemented using a hardware-style description
      of the operation.
      This version can print the coefficients fetched on-the-fly.
    Inputs:
      src_mem: Source memory holding the polynomial to be multiplied.
      dst_mem: Destination memory holding the resulting multiplied polynomial.
      monomial_exponent: The exponent of the monomial, i.e. X^monomial_exponent.
      modulo: The value of the modulo.
    Outputs:
    TODO:
     - [ ] Enable the commented-out print statements with a Verbose mode.
     - [ ] Generalise the offset calculation, that is currently hardcoded for
           N=512, R=8, and PSI=8.
    """
    # Addressing differs in order to get the coefficients on-the-fly
    monomial_exponent = 2 * N - monomial_exponent

    sector_offset = cols_per_sector * rows_per_sector
    new_sector_offset = (monomial_exponent >> 6) & (0b1111)
    new_row_offset = (monomial_exponent >> 3) & (0b111)
    new_col_offset = monomial_exponent & (0b111)
    # For debugging
    # print("New sector offset: ", new_sector_offset)
    # print("New row offset: ", new_row_offset)
    # print("New column offset: ", new_col_offset)

    # Get coefficient row-by-row
    for rows in range(rows_per_sector):

        # Create empty access list to check memory conflicts
        access_ll = []

        ## Next two for-loops are to be run in parallel in HW
        for sectors in range(nr_of_sectors):
            for cols in range(cols_per_sector):

                ## Check if row spills over
                if (cols + new_col_offset) < 8:
                    row_spillover = 0
                else:
                    row_spillover = 1

                ## Check if sector spills over
                if ((rows + new_row_offset) == rows_per_sector - 1) and (
                    row_spillover == 1
                ):
                    # There is a sector spillover when reading the last row and
                    # when there already is a row spillover.
                    sector_spillover = 1
                elif (rows + new_row_offset) >= 8:
                    # There is a sector spillover when the row offset on
                    # the current row exceeds the total number of rows.
                    sector_spillover = 1
                else:
                    # In the other cases, there is no sector spillover
                    sector_spillover = 0

                # Check if sign should be inverted
                if (
                    (sectors + sector_spillover + new_sector_offset) < nr_of_sectors
                ) or (
                    (sectors + sector_spillover + new_sector_offset)
                    >= 2 * nr_of_sectors
                ):
                    sign = 1
                else:
                    sign = -1

                # Intermediate values for index calculation
                coeff2_sector = (
                    sectors + sector_spillover + new_sector_offset
                ) % nr_of_sectors
                coeff2_column = (cols + new_col_offset) % cols_per_sector
                coeff2_row = (rows + new_row_offset + row_spillover) % rows_per_sector

                # Index of the column for coefficient 1
                idx1 = sectors * cols_per_sector + cols
                idx2 = coeff2_sector * cols_per_sector + coeff2_column
                access_ll.append([idx1, idx2])

                # Store the second coefficient in the destination memory for checking
                dst_mem[sectors][cols][rows] = (
                    sign * src_mem[coeff2_sector][coeff2_column][coeff2_row]
                ) % modulo

                # Print coefficients
                # print(
                #    f"        Coeff {sectors*64+rows*8+cols}: {src_mem[sectors][cols][rows]}"
                # )
                # print(
                #    f"Rotated Coeff {sectors*64+rows*8+cols}: {sign * src_mem[coeff2_sector][coeff2_column][coeff2_row]}"
                # )
                # print("")

        # Check for access conflicts, will exit if there are
        check_access_conflicts(access_ll)


# ==============================================================================
# main
# ==============================================================================
def main():
    """Main program
    Description:
      Main program testing the monomial multiplication in a hardware-style code
      against code using its definition.
      All 2N exponents are tested for N=512 on random polynomials.
      The polynomials are lists where the index i holds the coefficient of X^i.
    TODO:
     - [ ] Enable the commented-out print statements with a Verbose mode.
     - [ ] Extend the tests, they are currently only tested with N=512, R=8, and PSI=8.
    """
    # Set modulo
    q = 2**32

    # Create Memories for holding the acc & multiplied acc polynomials
    acc_mem = create_empty_mem()
    mm_acc_mem = create_empty_mem()

    # Initialise input polynomial for the monomial mult
    acc = []
    for i in range(N):
        # For polynomial containing the coefficient index
        acc.append(i)

    print("")
    print("")
    print(" Test For Reading Monomial Mult Results On-the-Fly")
    print("")
    nr_of_errors = 0

    ## Iterate over the possible monomial exponents for N=512
    for mm_index in range(2 * 512):

        # Initialise first memory with the original acc polynomial
        load_mem(acc, acc_mem)
        # For debugging
        # print_mem(acc_mem)

        # Fill second memory with the multiplied acc polynomial (for checking)
        monomial_mult_hw_on_the_fly(acc_mem, mm_acc_mem, mm_index, q)
        # For debugging
        # print_mem(mm_acc_mem)

        # Read the content of the destination memory into a 1D list for comparison
        flattened_mm_acc_mem = read_mem(mm_acc_mem)
        # Perform the monomial multiplication using the definition for comparison
        mm_acc = monomial_mult_definition(acc, mm_index, q)
        # For debugging
        # print(flattened_mm_acc_mem)
        # print(mm_acc)
        print(
            "Are the lists for exponent ",
            mm_index,
            " equal? ",
            flattened_mm_acc_mem == mm_acc,
        )
        if flattened_mm_acc_mem != mm_acc:
            nr_of_errors = nr_of_errors + 1

    print("")
    print("Number of errors: ", nr_of_errors)
    # If code gets here, it did not exit from access conflict error
    print("No access conflicts present")


if __name__ == "__main__":
    main()
