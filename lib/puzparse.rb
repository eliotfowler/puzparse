require "puzparse/version"

module Puzparse
  class Parser
    def initialize(filename)
      @filename = filename
    end

    def parse()
      # header
      checksum = read_puz_short(0x2, 0x00)
      magic = read_puz(0xC, 0x02)

      # component checksums
      cib_checksum = read_puz_short(0x2, 0x0E)
      masked_low_checksums = read_puz(0x4, 0x10)
      masked_high_checksums = read_puz(0x4, 0x14)

      # metadata
      version_string = read_puz(0x4, 0x18)
      reserved_1c = read_puz(0x2, 0x1C)
      scrambled_checksum = read_puz_short(0x2, 0x1E)
      reserved_20 = read_puz(0xC, 0x20)
      width = read_puz_int8(0x1, 0x2C)
      height = read_puz_int8(0x1, 0x2D)
      num_clues = read_puz_short(0x2, 0x2E)
      unknown_bitmask = read_puz_short(0x2, 0x30)
      scrambled_tag = read_puz_short(0x2, 0x32)

      # puzzle
      board = read_puz(width * height, 0x34)
      player_board = read_puz(width * height, 0x34 + (width * height))

      string_starting_byte = 0x34 + 2 * (width * height)

      # string metadata
      file = open(@filename)
      file.seek(string_starting_byte)

      string_sections_before_clues = [:title, :author, :copyright]
      string_sections_after_clues = [:notes]
      string_sections_values = {}

      num_string_sections = string_sections_before_clues.count +
                            string_sections_after_clues.count +
                            num_clues

      split_string = file.read.unpack("Z*" * num_string_sections)
      clues_arr = []

      for i in 0...num_string_sections
        if i < string_sections_before_clues.count
          string_sections_values[string_sections_before_clues[i]] = split_string[i].strip.force_encoding("ISO-8859-1").encode("UTF-8")
        elsif i < string_sections_before_clues.count + num_clues
          clues_arr << split_string[i]
        else
          idx = i - (string_sections_before_clues.count + num_clues)
          string_sections_values[string_sections_after_clues[idx]] = split_string[i].force_encoding("ISO-8859-1").encode("UTF-8")
        end
      end

      # An array mapping across clues to the "clue number".
      # So across_numbers[2] = 7 means that the 3rd across clue number
      # points at cell number 7.
      across_numbers = []
      down_numbers = []
      cell_numbers = []
      cell_numbers_1d = Array.new(width * height, 0)
      across_clues = []
      down_clues = []

      cur_cell_number = 1
      clue_index = 0

      for y in 0...height do
        for x in 0...width do
          next if is_black_cell(x, y, width, height, board)

          assigned_number = false

          if cell_needs_across_number(x, y, width, height, board)
            across_numbers << cur_cell_number
            cell_numbers[x] ||= []
            cell_numbers[x][y] = cur_cell_number
            assigned_number = true
            across_clues << "#{cur_cell_number}. #{clues_arr[clue_index]}".force_encoding("ISO-8859-1").encode("UTF-8")
            clue_index += 1
          end

          if cell_needs_down_number(x, y, width, height, board)
            down_numbers << cur_cell_number
            cell_numbers[x] ||= []
            cell_numbers[x][y] = cur_cell_number
            assigned_number = true
            down_clues << "#{cur_cell_number}. #{clues_arr[clue_index]}".force_encoding("ISO-8859-1").encode("UTF-8")
            clue_index += 1
          end

          if assigned_number
            cell_numbers_1d[cell_index_from_location(x, y, width)] = cur_cell_number
            cur_cell_number = cur_cell_number + 1
          else
            cell_numbers_1d[cell_index_from_location(x, y, width)] = 0
          end

        end
      end

      # format as json
      output_hash = {}
      output_hash[:title] = string_sections_values[:title]
      output_hash[:author] = string_sections_values[:author]
      output_hash[:clues] = {across: across_clues, down: down_clues}
      output_hash[:grid] = board.scan(/\S/)
      output_hash[:gridNums] = cell_numbers_1d
      output_hash[:gridSize] = {columns: width, rows: height}

      output_hash
    end

    private

    # Methods to read bytes from file
    def read_puz(length, offset)
      return IO.read(@filename, length, offset)
    end

    def read_puz_int8(length, offset)
      return read_puz(length, offset).unpack("C").first
    end

    def read_puz_short(length, offset)
      return read_puz(length, offset).unpack("S_").first
    end

    # Helper Methods
    def cell_index_from_location(x, y, width)
      return width * y + x
    end

    def location_from_cell_index(idx, widths)
      y = Integer(idx / width)
      x = idx - (y * width)
      return x, y
    end

    def is_black_cell (x, y, width, height, board)
      return true if (x < 0 || x >= width || y < 0 || y >= height)
      return board[cell_index_from_location(x, y, width)] == '.'
    end

    # Returns true if the cell at (x, y) gets an "across" clue number.
    def cell_needs_across_number (x, y, width, height, board)
      # Check that there is no blank to the left of us
      if (x == 0 || is_black_cell(x-1, y, width, height, board))
        # Check that there is space (at least two cells) for a word here
        return true if (x+1 < width && !is_black_cell(x+1, y, width, height, board))
      end

      return false
    end

    # Returns true if the cell at (x, y) gets an "down" clue number.
    def cell_needs_down_number (x, y, width, height, board)
      # Check that there is no blank to the above of us
      if (y == 0 || is_black_cell(x, y-1, width, height, board))
        # Check that there is space (at least two cells) for a word here
        return true if (y+1 < height && !is_black_cell(x, y+1, width, height, board))
      end

      return false
    end
  end
end
