module Txp
  # Verifies legacy PHPass portable hashes ($P$/$H$) from older Textpattern installs.
  module Phpass
    module_function

    ITOA64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    def check(password, stored)
      count_log2 = ITOA64.index(stored[3])
      return false if count_log2.nil? || count_log2 < 7 || count_log2 > 30

      count = 1 << count_log2
      salt = stored[4, 8]
      return false if salt.nil? || salt.length != 8

      hash = Digest::MD5.digest(salt + password)
      count.times { hash = Digest::MD5.digest(hash + password) }
      ActiveSupport::SecurityUtils.secure_compare(stored[0, 12] + encode64(hash, 16), stored)
    end

    def encode64(input, count)
      output = +""
      i = 0
      bytes = input.bytes
      while i < count
        value = bytes[i]
        i += 1
        output << ITOA64[value & 0x3f]
        value |= bytes[i] << 8 if i < count
        output << ITOA64[(value >> 6) & 0x3f]
        break if i >= count

        i += 1
        value |= bytes[i] << 16 if i < count
        output << ITOA64[(value >> 12) & 0x3f]
        break if i >= count

        i += 1
        output << ITOA64[(value >> 18) & 0x3f]
      end
      output
    end
  end
end
