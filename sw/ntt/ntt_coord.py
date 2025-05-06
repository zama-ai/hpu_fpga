#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Define a class to describe the Butterfly-unit (BU) and signal coordinates in an NTT.
#
# The NTT is characterized by a radix value : R, and the total number of points to be processed:
# R^S.
# This NTT is processed over S stages. Within each stage, a BU is used R^(S-1) times.
# Stages are numbered in the reversed order from input (S-1) to output (0).
# The NTT coordinates are used to identify the computation of a BU, and also its input
# and output points.
# ==============================================================================================

import sys  # manage errors
import math
import copy


class NttCoord:

    # ===============================================================================
    # init function
    # ===============================================================================
    def __init__(self, stage, length, coord, base, type_s=set()):
        """
        An NTT coordinate is available for a point or a BU.
        It is composed of:
        - its stage number. (NTT output is stage #0)
            For a BU, this corresponds to the stage the BU belongs to.
            For an input point this corresponds to the stage of the BU that processes this input.
            For an output point this corresponds to the stage of the BU that will process this
            output.
        - its length : number of digits in coord, expressed in 'base' unit. Note that a point have 1 additional digit
          than a BU.
        - its coordinate within the stage (coord)
        - base : unit in which the decomposition in digits is done.
        - type_s a set describing the type of the current object
        """
        self.stage = stage
        self.length = length
        self.coord = coord
        self.base = base
        self.type_s = type_s

        # Check
        if int(math.pow(2, int(math.log(base, 2)))) != base:
            sys.exit("> ERROR: NttCoord base should be a power of 2")

    # ===============================================================================
    # str function
    # ===============================================================================
    def __str__(self):
        d = {}
        d["stage"] = self.stage
        d["length"] = self.length
        d["coord"] = self.coord
        d["base"] = self.base
        d["type_s"] = self.type_s
        return "NttCoord: " + str(d)

    # ===============================================================================
    # repr function
    # ===============================================================================
    def __repr__(self):
        return self.__str__()

    # ===============================================================================
    # eq and ne functions
    # ===============================================================================
    def __eq__(self, other):
        if isinstance(other, self.__class__):
            eq = (
                (self.stage == other.stage)
                and (self.length == other.length)
                and (self.coord == other.coord)
                and (self.base == other.base)
                and (self.type_s == other.type_s)
            )
            return eq
        else:
            return False

    def __ne__(self, other):
        return not self.__eq__(other)

    # ===============================================================================
    #  add function
    # ===============================================================================
    def __add__(self, other):
        if not (
            (self.stage == other.stage)
            and (self.length == other.length)
            and (self.coord == other.coord)
            and (self.base == other.base)
        ):
            sys.exit(
                "ERROR> Coordinates cannot be added: {:s} {:s}".format(
                    str(self), str(other)
                )
            )
        result = NttCoord(
            self.stage, self.length, self.coord, self.base, self.type_s | other.type_s
        )

        return result

    # ===============================================================================
    # coord_2_digit
    # ===============================================================================
    def coord_2_digit(self):
        """
        Convert the coord into digit representation, which is a list of
        'length' elements, corresponding to the decomposition of coord in
        base 'base'.
        """
        digit_l = [0] * self.length

        coord = self.coord
        base_width = int(math.log(self.base, 2))
        mask = (1 << base_width) - 1
        for i in range(0, self.length):
            digit_l[i] = coord & mask
            coord = coord >> base_width
        return digit_l

    # ===============================================================================
    # digit_2_coord
    # ===============================================================================
    @classmethod
    def digit_2_coord(cls, digit_l, base):
        """
        Convert the digit list into a number.
        """
        coord = 0
        for i, d in enumerate(digit_l):
            coord = coord + d * int(math.pow(base, i))
        return coord

    # ===============================================================================
    # set_digit_2_coord
    # ===============================================================================
    def set_digit_2_coord(self, digit_l):
        """
        Convert the digit list into an coord.
        Set it to the NttCoord object
        """
        coord = NttCoord.digit_2_coord(digit_l, self.base)
        self.coord = coord

    # ===============================================================================
    # increment
    # ===============================================================================
    def inc(self, increment=1):
        """
        According to current stage and length, this function does a coord increment.
        Note that if the max value is reached (base^length), it will wrap around.
        """
        coord = self.coord + increment
        coord = coord % int(math.pow(self.base, self.length))
        self.coord = coord

    # ===============================================================================
    # get_point_position
    # ===============================================================================
    def get_point_position(self, direction="in"):
        """
        If the coordinate describes a point, this function gets the value
        of the position of the point within the BU interface.
        If the point is seen as an input, the position is given by the most significant digit.
        Else if the point is seen as an output, the position is given by the least significant
        digit.
        """
        if self.length == 1:
            sys.exit("ERROR> Is not a point, cannot do get_point_position.")

        digit_l = self.coord_2_digit()
        if direction == "in":
            return digit_l[-1]
        elif direction == "out":
            return digit_l[0]
        else:
            sys.exit("ERROR> Unknown direction : {:s}".format(direction))

    # ===============================================================================
    # get_bu_coord
    # ===============================================================================
    def get_bu_coord(self, direction="in"):
        """
        Consider current coordinate as a point coordinate.
        Extract from the coord the value of the associated BU.
        This depends on the direction we use to consider the point.
        """
        if self.length == 1:
            sys.exit("ERROR> Is not a point, cannot do get_bu_coord.")

        digit_l = self.coord_2_digit()

        if direction == "in":
            digit_l.pop(-1)
        elif direction == "out":
            digit_l.pop(0)
        else:
            sys.exit("ERROR> Unknown direction : {:s}".format(direction))

        return NttCoord.digit_2_coord(digit_l, self.base)

    # ===============================================================================
    # generate_output
    # ===============================================================================
    def create_output(self, position, type_s):
        """
        Current coord is a BU coordinate.
        Create an NttCoord object corresponding to the output <position> of this BU.
        """
        if position > self.base:
            sys.exit("ERROR> Cannot set a position greater than base")

        coord = self.coord * self.base + position
        return NttCoord(self.stage - 1, self.length + 1, coord, self.base, type_s)

    # ===============================================================================
    # belong_to
    # ===============================================================================
    @classmethod
    def belong_to(cls, bu_coord, in_point_coord):
        """
        The point is considered as an input of the BU.
        Check that this input belongs to this BU.
        Return True, if the point belongs to the BU.
        Return False, if the point does not belong to the BU.
        To check if a point belongs to a BU, keep the BU.length
        LSB digits of the point, they should be equal to the coord of the BU.
        """
        if (
            bu_coord.length + 1 != in_point_coord.length
            or bu_coord.base != in_point_coord.base
        ):
            sys.exit("ERROR> bu_coord and point_coord are not compatible")

        return (
            in_point_coord.get_bu_coord("in") == bu_coord.coord
            and bu_coord.stage == in_point_coord.stage
        )
