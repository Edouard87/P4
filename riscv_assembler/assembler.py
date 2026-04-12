from convert import AssemblyConverter as AC
import argparse
# instantiate object
# nibble mode means each 32 bit instruction will be devided into groups of 4 bits separated by space in output txt
convert = AC(output_mode = 'f', nibble_mode = False, hex_mode = False)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        prog="Simple RISC-V Assembler",
        description="Parse RISC-V Assembly",
    )
    parser.add_argument('input')
    parser.add_argument('output')
    args = parser.parse_args()
    convert(args.input, args.output)