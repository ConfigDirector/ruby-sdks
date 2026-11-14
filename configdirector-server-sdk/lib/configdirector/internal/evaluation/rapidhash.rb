# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      module Rapidhash
        LOW_64_BITS = 0xFFFF_FFFF_FFFF_FFFF

        SECRET = [
          0x2D35_8DCC_AA6C_78A5,
          0x8BB8_4B93_962E_ACC9,
          0x4B33_A62E_D433_D4A3,
          0x4D5A_2DA5_1DE1_AA47,
          0xA076_1D64_78BD_642F,
          0xE703_7ED1_A0B4_28DB,
          0x90ED_1765_281C_388C,
          0xAAAA_AAAA_AAAA_AAAA
        ].freeze

        SHORT_MESSAGE_LENGTH = 16
        BLOCK_LENGTH = 112
        LANE_COUNT = 7
        REMAINDER_PAIR_SECRETS = [2, 2, 1, 1, 2, 1].freeze

        def self.of(message, seed)
          length = message.bytesize
          seed ^= mix(seed ^ SECRET[2], SECRET[1])
          first_word, second_word, seed, last_block_length =
            if length <= SHORT_MESSAGE_LENGTH
              short_message_words(message, length, seed)
            else
              long_message_words(message, length, seed)
            end

          finish(first_word ^ SECRET[1], second_word ^ seed, last_block_length)
        end

        def self.short_message_words(message, length, seed)
          first_word, second_word =
            if length >= 8 then [read64(message, 0), read64(message, length - 8)]
            elsif length >= 4 then [read32(message, 0), read32(message, length - 4)]
            elsif length.positive? then tiny_message_words(message, length)
            else [0, 0]
            end

          [first_word, second_word, length >= 4 ? seed ^ length : seed, length]
        end

        def self.tiny_message_words(message, length)
          first_byte = read8(message, 0)
          first_word = read8(message, length - 1) | (((first_byte << 5) & 0xFF) << 40) | ((first_byte >> 3) << 48)

          [first_word, read8(message, length >> 1)]
        end

        def self.long_message_words(message, length, seed)
          remainder_offset, seed = blocks(message, length, seed)
          seed = remainder_pairs(message, remainder_offset, length, seed)
          last_block_length = length - remainder_offset

          [read64(message, length - 16) ^ last_block_length, read64(message, length - 8), seed, last_block_length]
        end

        def self.blocks(message, length, seed)
          return [0, seed] if length <= BLOCK_LENGTH

          lanes = Array.new(LANE_COUNT, seed)
          offset = 0
          loop do
            lanes = mix_block(message, offset, lanes)
            offset += BLOCK_LENGTH
            break if length - offset <= BLOCK_LENGTH
          end

          [offset, lanes.reduce(0) { |folded, lane| folded ^ lane }]
        end

        def self.mix_block(message, offset, lanes)
          lanes.each_with_index.map do |lane_seed, lane|
            lane_offset = offset + (lane * 16)
            mix(read64(message, lane_offset) ^ SECRET[lane], read64(message, lane_offset + 8) ^ lane_seed)
          end
        end

        def self.remainder_pairs(message, offset, length, seed)
          REMAINDER_PAIR_SECRETS.each_with_index do |secret, pair|
            pair_offset = offset + (pair * 16)
            break if length - pair_offset <= 16

            seed = mix(read64(message, pair_offset) ^ SECRET[secret], read64(message, pair_offset + 8) ^ seed)
          end
          seed
        end

        def self.mix(multiplicand, multiplier)
          product = multiplicand * multiplier
          (product & LOW_64_BITS) ^ (product >> 64)
        end

        def self.finish(first_word, second_word, last_block_length)
          product = first_word * second_word
          mix((product & LOW_64_BITS) ^ SECRET[7], (product >> 64) ^ SECRET[1] ^ last_block_length)
        end

        def self.read64(message, offset)
          message.unpack1("Q<", offset: offset).to_i
        end

        def self.read32(message, offset)
          message.unpack1("L<", offset: offset).to_i
        end

        def self.read8(message, offset)
          message.unpack1("C", offset: offset).to_i
        end

        private_constant :LOW_64_BITS, :SECRET, :SHORT_MESSAGE_LENGTH, :BLOCK_LENGTH, :LANE_COUNT,
                         :REMAINDER_PAIR_SECRETS
        private_class_method :short_message_words, :tiny_message_words, :long_message_words, :blocks, :mix_block,
                             :remainder_pairs, :mix, :finish, :read64, :read32, :read8
      end
    end
  end
end
