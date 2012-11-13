# A slightly patched version of https://github.com/junegunn/insensitive_hash v0.3.0
# that is not insensitive to underscores vs. strings.
#
# Copyright (c) 2011 Junegunn Choi
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
#                                                             "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InsensitiveHash < Hash
  class KeyClashError < Exception
  end

  def initialize default = nil, &block
    if block_given?
      raise ArgumentError.new('wrong number of arguments') unless default.nil?
      super &block
    else
      super
    end

    @key_map    = {}
    @safe       = false
  end

  # Sets whether to detect key clashes
  # @param [Boolean] 
  # @return [Boolean]
  def safe= s
    raise ArgumentError.new("Neither true nor false") unless [true, false].include?(s)
    @safe = s
  end

  # @return [Boolean] Key-clash detection enabled?
  def safe?
    @safe
  end
  
  # Returns a normal, sensitive Hash
  # @return [Hash]
  def to_hash
    {}.merge self
  end
  alias sensitive to_hash

  def self.[] *init
    h = Hash[*init]
    InsensitiveHash.new.tap do |ih|
      ih.merge! h
    end
  end

  %w[[] assoc has_key? include? key? member?].each do |symb|
    class_eval <<-EVAL
      def #{symb} key
        super lookup_key(key)
      end
    EVAL
  end

  def []= key, value
    delete key
    ekey = encode key
    @key_map[ekey] = key
    super key, value
  end
  alias store []=

  def merge! other_hash
    detect_clash other_hash
    other_hash.each do |key, value|
      deep_set key, value
    end
    self
  end
  alias update! merge!

  def merge other_hash
    InsensitiveHash.new.tap do |ih|
      ih.replace self
      ih.merge! other_hash
    end
  end
  alias update merge

  def delete key, &block
    super lookup_key(key, true), &block
  end

  def clear
    @key_map.clear
    super
  end

  def replace other
    super other

    self.safe = other.respond_to?(:safe?) ? other.safe? : safe?

    @key_map.clear
    self.each do |k, v|
      ekey = encode k
      @key_map[ekey] = k
    end
  end

  def shift
    super.tap do |ret|
      @key_map.delete_if { |k, v| v == ret.first }
    end
  end

  def values_at *keys
    keys.map { |k| self[k] }
  end

  def fetch *args, &block
    args[0] = lookup_key(args[0]) if args.first
    super *args, &block
  end

  def dup
    super.tap { |copy|
      copy.instance_variable_set :@key_map, @key_map.dup
    }
  end

  def clone
    super.tap { |copy|
      copy.instance_variable_set :@key_map, @key_map.dup
    }
  end

private
  def deep_set key, value
    wv = wrap value
    self[key] = wv
  end

  def wrap value
    case value
    when InsensitiveHash
      value
    when Hash
      InsensitiveHash[value]
    when Array
      value.map { |v| wrap v }
    else
      value
    end
  end

  def lookup_key key, delete = false
    ekey = encode key
    if @key_map.has_key?(ekey)
      delete ? @key_map.delete(ekey) : @key_map[ekey]
    else
      key
    end
  end

  def encode key
    case key
    when String, Symbol
      key.to_s.downcase
    else
      key
    end
  end

  def detect_clash hash
    hash.keys.map { |k| encode k }.tap { |ekeys|
      raise KeyClashError.new("Key clash detected") if ekeys != ekeys.uniq
    } if @safe
  end
end
