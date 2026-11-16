# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Value::ServedText do
  def typed(value)
    ConfigDirector::Internal::Value::TypedValue.new(value: value)
  end

  it "reads true for a boolean" do
    expect(described_class.typed_as(:boolean, "true", "boolean")).to eq(typed(true))
  end

  it "reads false for a boolean" do
    expect(described_class.typed_as(:boolean, "false", "boolean")).to eq(typed(false))
  end

  it "reads a boolean written in capital letters" do
    expect(described_class.typed_as(:boolean, "TRUE", "boolean")).to eq(typed(true))
  end

  it "does not read a boolean from 1" do
    expect(described_class.typed_as(:boolean, "1", "integer")).to eq("invalid-boolean")
  end

  it "does not read a boolean from text that folds to false only outside ASCII" do
    expect(described_class.typed_as(:boolean, "falſe", "string")).to eq("invalid-boolean")
  end

  it "does not read a boolean from text with a space around it" do
    expect(described_class.typed_as(:boolean, " true", "string")).to eq("invalid-boolean")
  end

  it "reads the text of a string config" do
    expect(described_class.typed_as(:string, "Monday", "string")).to eq(typed("Monday"))
  end

  it "reads the text of an enum config" do
    expect(described_class.typed_as(:string, "large", "enum")).to eq(typed("large"))
  end

  it "reads the text of a url config" do
    expect(described_class.typed_as(:string, "https://example.com", "url")).to eq(typed("https://example.com"))
  end

  it "reads the text of a config whose type the SDK does not know" do
    expect(described_class.typed_as(:string, "P1D", "duration")).to eq(typed("P1D"))
  end

  it "does not read a String from a boolean config" do
    expect(described_class.typed_as(:string, "true", "boolean")).to eq("type-mismatch")
  end

  it "does not read a String from a float config" do
    expect(described_class.typed_as(:string, "26.5", "float")).to eq("type-mismatch")
  end

  it "reads an Integer" do
    expect(described_class.typed_as(:integer, "42", "integer").value).to eql(42)
  end

  it "reads a negative Integer" do
    expect(described_class.typed_as(:integer, "-42", "integer").value).to eql(-42)
  end

  it "reads an Integer with a leading zero as a decimal number" do
    expect(described_class.typed_as(:integer, "010", "integer").value).to eql(10)
  end

  it "reads an Integer beyond 64 bits exactly" do
    expect(described_class.typed_as(:integer, "36893488147419103233", "integer").value)
      .to eql(36_893_488_147_419_103_233)
  end

  it "reads an Integer from a whole number written with a decimal point" do
    expect(described_class.typed_as(:integer, "26.0", "float").value).to eql(26)
  end

  it "reads an Integer from a whole number written with an exponent" do
    expect(described_class.typed_as(:integer, "1e3", "float").value).to eql(1000)
  end

  it "does not read an Integer from a number with a fraction" do
    expect(described_class.typed_as(:integer, "26.5", "float")).to eq("invalid-number")
  end

  it "does not read an Integer from a hexadecimal number" do
    expect(described_class.typed_as(:integer, "0x1A", "string")).to eq("invalid-number")
  end

  it "does not read an Integer from digits separated by an underscore" do
    expect(described_class.typed_as(:integer, "1_000", "string")).to eq("invalid-number")
  end

  it "does not read an Integer from a number with a space around it" do
    expect(described_class.typed_as(:integer, " 42", "string")).to eq("invalid-number")
  end

  it "does not read an Integer from a number followed by a line break" do
    expect(described_class.typed_as(:integer, "42\n", "string")).to eq("invalid-number")
  end

  it "reads an Integer of 401 digits exactly" do
    expect(described_class.typed_as(:integer, "1#{"0" * 400}", "integer").value).to eql(10**400)
  end

  it "does not read an Integer from a number with an exponent too large to be a finite Float" do
    expect(described_class.typed_as(:integer, "1e400", "float")).to eq("invalid-number")
  end

  it "reads a Float" do
    expect(described_class.typed_as(:float, "26.5", "float").value).to eql(26.5)
  end

  it "reads a Float from a whole number" do
    expect(described_class.typed_as(:float, "42", "integer").value).to eql(42.0)
  end

  it "reads a Float written with an exponent" do
    expect(described_class.typed_as(:float, "2.5e-3", "float").value).to eql(0.0025)
  end

  it "reads a Float that ends with its decimal point" do
    expect(described_class.typed_as(:float, "5.", "float").value).to eql(5.0)
  end

  it "does not read a Float from Infinity" do
    expect(described_class.typed_as(:float, "Infinity", "string")).to eq("invalid-number")
  end

  it "does not read a Float from NaN" do
    expect(described_class.typed_as(:float, "NaN", "string")).to eq("invalid-number")
  end

  it "does not read a Float from a number too large to be finite" do
    expect(described_class.typed_as(:float, "1e999", "float")).to eq("invalid-number")
  end

  it "does not read a Float from a sign without digits" do
    expect(described_class.typed_as(:float, "-", "string")).to eq("invalid-number")
  end

  it "reads a JSON object as a Hash" do
    expect(described_class.typed_as(:json_object, '{"sizes":[1,2.5,null,true]}', "json"))
      .to eq(typed({ "sizes" => [1, 2.5, nil, true] }))
  end

  it "reads a JSON array as an Array" do
    expect(described_class.typed_as(:json_array, '[{"size":"small"}]', "json")).to eq(typed([{ "size" => "small" }]))
  end

  it "keeps the last value of a key that a JSON object holds twice" do
    expect(described_class.typed_as(:json_object, '{"size":"small","size":"large"}', "json"))
      .to eq(typed({ "size" => "large" }))
  end

  it "does not read a Hash from a JSON array" do
    expect(described_class.typed_as(:json_object, "[1]", "json")).to eq("invalid-json")
  end

  it "does not read an Array from a JSON object" do
    expect(described_class.typed_as(:json_array, '{"size":1}', "json")).to eq("invalid-json")
  end

  it "does not read a Hash from a JSON number" do
    expect(described_class.typed_as(:json_object, "42", "integer")).to eq("invalid-json")
  end

  it "does not read an Array from malformed JSON" do
    expect(described_class.typed_as(:json_array, "[1,", "json")).to eq("invalid-json")
  end

  it "does not read an Array from JSON that holds NaN" do
    expect(described_class.typed_as(:json_array, "[NaN]", "json")).to eq("invalid-json")
  end

  it "does not build an object of a class the JSON names" do
    expect(described_class.typed_as(:json_object, '{"json_class":"String","raw":[104,105]}', "json"))
      .to eq(typed({ "json_class" => "String", "raw" => [104, 105] }))
  end

  it "reports a missing value for an empty value, whatever is read" do
    expect(described_class.typed_as(:boolean, "", "boolean")).to eq("value-missing")
  end

  it "reports a missing value for no value" do
    expect(described_class.typed_as(:string, nil, "string")).to eq("value-missing")
  end

  it "reads a whole number of 16,384 digits" do
    expect(described_class.typed_as(:integer, "7" * 16_384, "integer")).to eq(typed(((10**16_384) - 1) / 9 * 7))
  end

  it "reads a negative whole number of 16,384 digits" do
    expect(described_class.typed_as(:integer, "-#{"7" * 16_384}", "integer")).to eq(
      typed(-(((10**16_384) - 1) / 9 * 7))
    )
  end

  it "does not read a negative whole number of 16,385 digits" do
    expect(described_class.typed_as(:integer, "-#{"7" * 16_385}", "integer")).to eq("invalid-number")
  end

  it "does not read a whole number of 16,385 digits" do
    expect(described_class.typed_as(:integer, "7" * 16_385, "integer")).to eq("invalid-number")
  end

  it "does not read a JSON array that holds a number of 16,385 digits" do
    expect(described_class.typed_as(:json_array, "[#{"7" * 16_385}]", "json")).to eq("invalid-json")
  end

  it "does not create an object of the class a JSON object names" do
    stub_const("ClassThatJsonCouldCreate", Class.new { def self.json_create(_json_object) = new })
    served_text = '{"json_class":"ClassThatJsonCouldCreate"}'

    expect(described_class.typed_as(:json_object, served_text, "json")).to eq(
      typed({ "json_class" => "ClassThatJsonCouldCreate" })
    )
  end
end
