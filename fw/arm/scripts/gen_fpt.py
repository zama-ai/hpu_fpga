#!/usr/bin/env python3

# Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT

#
# Generate FPT binary from JSON file
#
import json
import argparse
from collections import namedtuple


# Constants
FIELD_SIZE_U32 = 4
FIELD_SIZE_U8 = 1
TYPE_PDI = '0x00000E00'


# Debug class uses to dump hex output
class hexdump:
    def __init__(self, buf, off=0):
        self.buf = buf
        self.off = off

    def __iter__(self):
        last_bs, last_line = None, None
        for i in range(0, len(self.buf), 16):
            bs = bytearray(self.buf[i : i + 16])
            line = "{:08x}  {:23}  {:23}  |{:16}|".format(
                self.off + i,
                " ".join(("{:02x}".format(x) for x in bs[:8])),
                " ".join(("{:02x}".format(x) for x in bs[8:])),
                "".join((chr(x) if 32 <= x < 127 else "." for x in bs)),
            )
            if bs == last_bs:
                line = "*"
            if bs != last_bs or line != last_line:
                yield line
            last_bs, last_line = bs, line
        yield "{:08x}".format(self.off + len(self.buf))

    def __str__(self):
        return "\n".join(self)

    def __repr__(self):
        return "\n".join(self)


# The main loop
def main():
    parser = argparse.ArgumentParser(description='Generate binary file from FPT JSON',
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-f', '--file', help='the FPT JSON file')
    parser.add_argument('-v', '--verbose', help="increase output verbosity")
    args = parser.parse_args()
    if args.file is None:
        print('Error: Please specifiy a valid FPT JSON file')
        parser.print_help()
        raise SystemExit(1)

    # Step1: open the JSON file
    try:
        if args.verbose:
            print('Input filename:' + args.file)
        fp = open(args.file)
    except Exception as e:
        print('Error: Failed to open file: ' + str(e))
        raise SystemExit(1)

    # Step2: load the JSON file
    try:
        data = json.load(fp)
    except Exception as e:
        print('Error: Failed to load JSON data: ' + str(e))
        raise SystemExit(1)
    finally:
        # Finished with the file
        fp.close()

    # Step3: Parse the FPT header from the JSON
    try:
        fpt_entry_size = data['fpt_header(0)']['fpt_entry_size'] 
        fpt_header_size = data['fpt_header(0)']['fpt_header_size']
        fpt_version = data['fpt_header(0)']['fpt_version']
        magic_word = data['fpt_header(0)']['magic_word']
        num_entries = data['fpt_header(0)']['num_entries']
        if args.verbose:
            print('fpt_header:', data['fpt_header(0)'])
    except Exception as e:
        print('Error: FPT header not as expected: ' + str(e))
        raise SystemExit(1)

    # Step4: Parse the FPT enteries from the JSON
    try:
        fpt_entry = namedtuple('fpt_entry', 'type base_addr partition_size')
        fpt_entry_list = []
        for x in range(0, int(num_entries)):
            fpt_str = "fpt_entry(0, " + str(x) + ")"
            fpt_entry_list.append(fpt_entry(data[fpt_str]['type'],
                                  data[fpt_str]['base_addr'],
                                  data[fpt_str]['partition_size']))
        if args.verbose:
            print('magic_word:', magic_word)
            print('num_entries:', num_entries)
            print('fpt_version:', fpt_version)
            print('fpt_header_size:', fpt_header_size)
            print('fpt_entry_size:', fpt_entry_size)
            for fpt_tuple in fpt_entry_list:
                print(fpt_tuple)
    except Exception as e:
        print('Error: Failed to parse the FPT enteries: ' + str(e))
        raise SystemExit(1)

    # Step5: Create an empty byte array of fixed size & populate
    try:
        fpt_size = fpt_header_size + (fpt_entry_size * num_entries)
        fpt_data = bytearray(fpt_size)
        pos = 0
        # reverse as little endian
        magic_bytes = bytearray.fromhex(magic_word[2:])
        magic_bytes.reverse()
        fpt_data[pos:0] = magic_bytes
        pos += FIELD_SIZE_U32
        fpt_data.insert(pos, fpt_version)
        pos += FIELD_SIZE_U8
        fpt_data.insert(pos, fpt_header_size)
        pos += FIELD_SIZE_U8
        fpt_data.insert(pos, fpt_entry_size)
        pos += FIELD_SIZE_U8
        fpt_data.insert(pos, num_entries)

        index_tuple = 0
        for fpt_tuple in fpt_entry_list:
            pos = fpt_header_size + (fpt_entry_size * index_tuple)
            if fpt_tuple.type == 'PDI':
                type_bytes = bytearray.fromhex(TYPE_PDI[2:])
                type_bytes.reverse()
                fpt_data[pos:0] = type_bytes
            else:
                raise Exception('Invalid type field found, only PDI is supported')
            pos += FIELD_SIZE_U32
            base_addr_bytes = bytearray.fromhex((fpt_tuple.base_addr)[2:])
            base_addr_bytes.reverse()
            fpt_data[pos:0] = base_addr_bytes
            pos += FIELD_SIZE_U32
            partition_size_bytes = bytearray.fromhex((fpt_tuple.partition_size)[2:])
            partition_size_bytes.reverse()
            fpt_data[pos:0] = partition_size_bytes
            index_tuple += 1

        if args.verbose:
            # dump out the generated FPT
            print(hexdump(fpt_data))
    except Exception as e:
        print('Error: Failed to populate FPT data array: ' + str(e))
        raise SystemExit(1)

    # Step6: Write bytearray to binary file
    try:
        with open("fpt.bin", 'wb') as fp:
            fp.write(fpt_data)
            print('Successfully generated binary fpt.bin...')
    except Exception as e:
        print(e)

if __name__ == '__main__':
    main()
