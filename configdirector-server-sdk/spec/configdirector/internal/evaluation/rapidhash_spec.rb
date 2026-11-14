# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::Rapidhash do
  seed = 0x397832987

  it "hashes an empty message as the reference implementation does" do
    expect(described_class.of("", seed)).to eq(5_377_612_543_505_373_799)
  end

  it "hashes one byte as the reference implementation does" do
    expect(described_class.of("a", seed)).to eq(7_674_800_498_429_868_151)
  end

  it "hashes two bytes as the reference implementation does" do
    expect(described_class.of("ab", seed)).to eq(12_048_270_741_005_468_339)
  end

  it "hashes three bytes as the reference implementation does" do
    expect(described_class.of("abc", seed)).to eq(8_205_525_400_821_834_274)
  end

  it "hashes four bytes as the reference implementation does" do
    expect(described_class.of("abcd", seed)).to eq(2_559_843_570_930_408_943)
  end

  it "hashes five bytes as the reference implementation does" do
    expect(described_class.of("abcde", seed)).to eq(17_182_111_687_207_956_362)
  end

  it "hashes seven bytes as the reference implementation does" do
    expect(described_class.of("abcdefg", seed)).to eq(13_135_472_276_134_024_436)
  end

  it "hashes eight bytes as the reference implementation does" do
    expect(described_class.of("abcdefgh", seed)).to eq(10_825_195_283_420_988_801)
  end

  it "hashes nine bytes as the reference implementation does" do
    expect(described_class.of("abcdefghi", seed)).to eq(9_324_307_379_318_471_710)
  end

  it "hashes sixteen bytes as the reference implementation does" do
    expect(described_class.of("0123456789abcdef", seed)).to eq(8_410_398_172_536_096_822)
  end

  it "hashes seventeen bytes as the reference implementation does" do
    expect(described_class.of("0123456789abcdefg", seed)).to eq(8_975_841_632_926_530_338)
  end

  it "hashes a bucketing input as the reference implementation does" do
    expect(described_class.of("10-11111111-1111-4111-8111-111111111111", seed)).to eq(7_715_065_197_445_012_089)
  end

  it "hashes the contract's user vector as the contract states" do
    expect(described_class.of("user-1-11111111-1111-4111-8111-111111111111", seed)).to eq(0xe9679cfc0acbbabe)
  end

  it "hashes forty-eight bytes as the reference implementation does" do
    expect(described_class.of("x" * 48, seed)).to eq(1_185_046_273_860_983_588)
  end

  it "hashes ninety-seven bytes, which reach every remainder pair, as the reference implementation does" do
    expect(described_class.of("t" * 97, seed)).to eq(6_277_733_333_604_503_958)
  end

  it "hashes one full block as the reference implementation does" do
    expect(described_class.of("y" * 112, seed)).to eq(5_679_430_438_346_846_087)
  end

  it "hashes one block and one byte as the reference implementation does" do
    expect(described_class.of("z" * 113, seed)).to eq(14_103_938_338_420_400_619)
  end

  it "hashes two blocks and a remainder as the reference implementation does" do
    expect(described_class.of("w" * 240, seed)).to eq(15_088_383_192_705_595_115)
  end

  it "hashes multi-byte UTF-8 as the reference implementation does" do
    expect(described_class.of("héllo wörld ✓", seed)).to eq(7_481_766_294_562_949_397)
  end
end
