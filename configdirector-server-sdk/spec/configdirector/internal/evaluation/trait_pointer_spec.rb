# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::TraitPointer do
  it "selects a nested member" do
    expect(described_class.value_at("/team/name", { "team" => { "name" => "core" } })).to eq("core")
  end

  it "selects a member with a slash in its name through an escaped slash" do
    expect(described_class.value_at("/a~1b", { "a/b" => 1, "m~n" => 2 })).to eq(1)
  end

  it "selects a member with a tilde in its name through an escaped tilde" do
    expect(described_class.value_at("/m~0n", { "a/b" => 1, "m~n" => 2 })).to eq(2)
  end

  it "decodes an escaped slash before an escaped tilde" do
    expect(described_class.value_at("/~01", { "~1" => "x", "/" => "y" })).to eq("x")
  end

  it "selects the member with an empty name with a single slash" do
    expect(described_class.value_at("/", { "" => { "" => "x" } })).to eq({ "" => "x" })
  end

  it "selects nested members with empty names with two slashes" do
    expect(described_class.value_at("//", { "" => { "" => "x" } })).to eq("x")
  end

  it "selects a member with an empty name after a trailing slash" do
    expect(described_class.value_at("/a/", { "a" => { "" => "x" } })).to eq("x")
  end

  it "selects nothing with an invalid escape" do
    expect(described_class.value_at("/~2", { "~2" => "x" })).to be_nil
  end

  it "selects nothing with a trailing tilde" do
    expect(described_class.value_at("/a~", { "a~" => "x" })).to be_nil
  end

  it "selects nothing without a leading slash" do
    expect(described_class.value_at("foo", { "foo" => "x" })).to be_nil
  end

  it "selects nothing with a URI fragment pointer" do
    expect(described_class.value_at("#/foo", { "foo" => "x" })).to be_nil
  end

  it "selects nothing with an empty pointer" do
    expect(described_class.value_at("", { "foo" => "x" })).to be_nil
  end

  it "does not decode percent-encoding" do
    expect(described_class.value_at("/%25", { "%25" => "x", "%" => "y" })).to eq("x")
  end

  it "selects an array element by its index" do
    expect(described_class.value_at("/list/1", { "list" => %w[a b] })).to eq("b")
  end

  it "selects nothing with an index with a leading zero" do
    expect(described_class.value_at("/list/01", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with a signed index" do
    expect(described_class.value_at("/list/+1", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with a negative index" do
    expect(described_class.value_at("/list/-1", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with the end of array marker" do
    expect(described_class.value_at("/list/-", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with an index past the end" do
    expect(described_class.value_at("/list/2", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with an index too large for a machine integer" do
    expect(described_class.value_at("/list/99999999999999999999", { "list" => %w[a b] })).to be_nil
  end

  it "selects nothing with an index of non-ASCII digits" do
    expect(described_class.value_at("/list/١", { "list" => %w[a b] })).to be_nil
  end

  it "does not index a string by character" do
    expect(described_class.value_at("/s/0", { "s" => "abc" })).to be_nil
  end

  it "selects nothing below a missing member" do
    expect(described_class.value_at("/missing/name", { "team" => { "name" => "core" } })).to be_nil
  end

  it "selects nothing below a null member" do
    expect(described_class.value_at("/team/name", { "team" => nil })).to be_nil
  end

  it "selects a member named with digits from an object" do
    expect(described_class.value_at("/7", { "7" => "x" })).to eq("x")
  end

  it "selects a member named with a leading zero from an object" do
    expect(described_class.value_at("/01", { "01" => "x" })).to eq("x")
  end
end
