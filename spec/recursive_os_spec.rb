require "recursive_os"

describe RecursiveOpenStruct do
  it "can respond to a string key query" do
    ros = RecursiveOpenStruct.new({:a1 => {:b1 => "b1", :b2 => {:c1 => "c1", :c2 => {:d1 => "d1"}}}, :a2 => "a2"})
    expect(ros.key_exists?("a1")).to be_true
    expect(ros.key_exists?("a3")).to be_false
    expect(ros.key_exists?("b1")).to be_false
    expect(ros.key_exists?("a1.b1")).to be_true
    expect(ros.key_exists?("a1.b3")).to be_false
    expect(ros.key_exists?("a1.b2.c1")).to be_true
    expect(ros.key_exists?("a1.b2.c2.d1")).to be_true
    expect(ros.key_exists?("c2.d1")).to be_false
  end

  it "can be updateed with a pair of a specified key and a value" do
    ros = RecursiveOpenStruct.new({:a1 => {:b1 => "b1", :b2 => {:c1 => "c1", :c2 => {:d1 => "d1"}}}, :a2 => "a2"})
    ros.update_value!("a2", "A2")
    expect(ros.a2).to eq("A2")
    ros.update_value!("a1.b3.new_key", "NEW_KEY")
    expect(ros.a1.b3.new_key).to eq("NEW_KEY")
    ros.update_value!("a1.b2.c2.d1", "D1")
    expect(ros.a1.b2.c2.d1).to eq("D1")
  end
end
