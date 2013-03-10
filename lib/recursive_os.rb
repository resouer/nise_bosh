require 'recursive-open-struct'

class RecursiveOpenStruct
  def key_exists?(key)
    key = key.split(".") if key.is_a?(String)
    return false unless respond_to?(key.first)
    if key.size > 1
      return send(key.first).key_exists?(key[1..-1])
    else
      return true
    end
  end

  def update_value!(key, value)
    key = key.split(".") if key.is_a?(String)
    if key.size > 1
      if !respond_to?(key.first)
        new_ostruct_member(key.first)
        v = self.class.new
      else
        v = send(key.first)
        unless v.is_a?(self.class)
          raise "Not supported class in the given key: #{v.class}"
        end
      end
      n = v.update_value!(key[1..-1], value)
      send("#{key.first}=", n)
    else
      send("#{key.first}=", value)
    end
    self
  end
end
