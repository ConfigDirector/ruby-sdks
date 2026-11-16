# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::CompactJsonText do
  it "writes a Hash and an Array without spaces" do
    expect(described_class.of({ "greeting" => "hi", "sizes" => [1, 2] })).to eq('{"greeting":"hi","sizes":[1,2]}')
  end

  it "writes true, false and nil as JSON does" do
    expect(described_class.of([true, false, nil])).to eq("[true,false,null]")
  end

  it "writes a whole Float without a fraction" do
    expect(described_class.of([2.0, -0.0])).to eq("[2,0]")
  end

  it "writes a large and a small Float with the exponent JavaScript writes" do
    expect(described_class.of([1e21, 1e-7, 1.5])).to eq("[1e+21,1e-7,1.5]")
  end

  it "writes a Float that is not finite as null" do
    expect(described_class.of([Float::INFINITY, -Float::INFINITY, Float::NAN])).to eq("[null,null,null]")
  end

  it "writes an Integer of any size with all its digits" do
    expect(described_class.of([12_345_678_901_234_567_890])).to eq("[12345678901234567890]")
  end

  it "writes an Integer larger than the largest Float as null" do
    expect(described_class.of([10**400, -(10**400), 10**300])).to eq("[null,null,1#{"0" * 300}]")
  end

  it "escapes quotes, backslashes and control characters, and no other character" do
    expect(described_class.of(["é \n\"\\/\u0001\u007f"])).to eq("[\"é \\n\\\"\\\\/\\u0001\u007f\"]")
  end

  it "writes a Symbol key and a Symbol as their names" do
    expect(described_class.of({ plan: :pro })).to eq('{"plan":"pro"}')
  end

  it "writes a key that is not text as its text" do
    expect(described_class.of({ 1 => "one" })).to eq('{"1":"one"}')
  end

  it "writes an object of another class as its text" do
    expect(described_class.of([Time.utc(2026, 11, 15, 9, 30)])).to eq('["2026-11-15 09:30:00 UTC"]')
  end

  it "writes the bytes of a text that are not valid UTF-8 as the replacement character" do
    expect(described_class.of(["caf\xE9".b])).to eq("[\"caf�\"]")
  end

  it "writes a text in another encoding as UTF-8" do
    expect(described_class.of(["café".encode(Encoding::ISO_8859_1)])).to eq('["café"]')
  end

  it "writes an Array that holds itself as null where it holds itself" do
    array_holding_itself = [1]
    array_holding_itself << array_holding_itself

    expect(described_class.of(array_holding_itself)).to eq("[1,null]")
  end

  it "writes a Hash that holds itself as null where it holds itself" do
    hash_holding_itself = { "name" => "loop" }
    hash_holding_itself["self"] = hash_holding_itself

    expect(described_class.of(hash_holding_itself)).to eq('{"name":"loop","self":null}')
  end

  it "writes the same Array twice when it is held twice without holding itself" do
    sizes = [1, 2]

    expect(described_class.of({ "first" => sizes, "second" => sizes })).to eq('{"first":[1,2],"second":[1,2]}')
  end

  it "writes null in place of an Array nested below 100 levels" do
    nested = 101.times.reduce([]) { |inner, _level| [inner] }

    expect(described_class.of(nested)).to eq("#{"[" * 100}null#{"]" * 100}")
  end
end
