# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Value::ParsedJson do
  it "reads JSON text" do
    expect(described_class.of('{"sizes":[1,2.5,"large"]}')).to eq({ "sizes" => [1, 2.5, "large"] })
  end

  it "keeps the last of a key given twice" do
    expect(described_class.of('{"size":1,"size":2}')).to eq({ "size" => 2 })
  end

  it "raises the parser's error for text that is not JSON, without repeating the text" do
    expect { described_class.of("not-json-and-not-to-be-repeated") }.to raise_error(
      JSON::ParserError, "it is not valid JSON"
    )
  end

  it "reads a number of 16,384 digits" do
    expect(described_class.of("[#{"7" * 16_384}]")).to eq([((10**16_384) - 1) / 9 * 7])
  end

  it "raises the parser's error for a number of 16,385 digits" do
    expect { described_class.of("[#{"7" * 16_385}]") }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "raises the parser's error for a number with a fraction of 16,385 digits" do
    expect { described_class.of("[0.#{"7" * 16_385}]") }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "raises the parser's error for a number of 16,385 digits between two comments that hold a quote" do
    json_text = "/* \" */ [#{"7" * 16_385}] /* \" */"

    expect { described_class.of(json_text) }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "raises the parser's error for a number of 16,385 digits after two comments in a row" do
    json_text = "/* one *//* two */ [#{"7" * 16_385}]"

    expect { described_class.of(json_text) }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "raises the parser's error for a number of 16,385 digits after a comment that ends with its line" do
    json_text = "// a comment with a \" quote\n[#{"7" * 16_385}]"

    expect { described_class.of(json_text) }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "reads a string of 16,385 digits" do
    expect(described_class.of("[\"#{"7" * 16_385}\"]")).to eq(["7" * 16_385])
  end

  it "reads a string of 16,385 digits that follows a string with an escaped quote and a backslash" do
    json_text = "[\"a \\\" quote and a backslash \\\\\", \"#{"7" * 16_385}\"]"

    expect(described_class.of(json_text)).to eq(['a " quote and a backslash \\', "7" * 16_385])
  end

  it "raises the parser's error for a number of 16,385 digits that follows a string with an escaped quote" do
    json_text = "[\"an escaped \\\" quote\", #{"7" * 16_385}]"

    expect { described_class.of(json_text) }.to raise_error(
      JSON::ParserError, "it holds a number of more than 16,384 digits"
    )
  end

  it "raises the parser's error for a string of 16,385 digits that never ends, as for any text that is not JSON" do
    expect { described_class.of("[\"#{"7" * 16_385}") }.to raise_error(JSON::ParserError, "it is not valid JSON")
  end

  it "reads text that holds bytes that are not UTF-8 beside 16,385 digits in a string" do
    json_text = "[\"\xFF #{"7" * 16_385}\"]"

    expect(described_class.of(json_text)).to eq(["\xFF #{"7" * 16_385}"])
  end
end
