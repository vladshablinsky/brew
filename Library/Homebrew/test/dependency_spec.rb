require "dependency"

describe Dependency do
  alias_matcher :be_a_build_dependency, :be_build
  alias_matcher :be_a_runtime_dependency, :be_run

  describe "::new" do
    it "accepts a single tag" do
      dep = described_class.new("foo", %w[bar])
      expect(dep.tags).to eq(%w[bar])
    end

    it "accepts multiple tags" do
      dep = described_class.new("foo", %w[bar baz])
      expect(dep.tags.sort).to eq(%w[bar baz].sort)
    end

    it "preserves symbol tags" do
      dep = described_class.new("foo", [:build])
      expect(dep.tags).to eq([:build])
    end

    it "accepts symbol and string tags" do
      dep = described_class.new("foo", [:build, "bar"])
      expect(dep.tags).to eq([:build, "bar"])
    end
  end

  describe "::merge_repeats" do
    it "merges duplicate dependencies" do
      dep = described_class.new("foo", [:build], nil, "foo")
      dep2 = described_class.new("foo", ["bar"], nil, "foo2")
      dep3 = described_class.new("xyz", ["abc"], nil, "foo")
      merged = described_class.merge_repeats([dep, dep2, dep3])
      expect(merged.count).to eq(2)
      expect(merged.first).to be_a described_class

      foo_named_dep = merged.find { |d| d.name == "foo" }
      expect(foo_named_dep.tags).to eq(["bar"])
      expect(foo_named_dep.option_names).to include("foo")
      expect(foo_named_dep.option_names).to include("foo2")

      xyz_named_dep = merged.find { |d| d.name == "xyz" }
      expect(xyz_named_dep.tags).to eq(["abc"])
      expect(xyz_named_dep.option_names).to include("foo")
      expect(xyz_named_dep.option_names).not_to include("foo2")
    end

    it "merges necessity tags" do
      required_dep = described_class.new("foo")
      recommended_dep = described_class.new("foo", [:recommended])
      optional_dep = described_class.new("foo", [:optional])

      deps = described_class.merge_repeats([required_dep, recommended_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = described_class.merge_repeats([required_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = described_class.merge_repeats([recommended_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_required
      expect(deps.first).to be_recommended
      expect(deps.first).not_to be_optional
    end

    it "merges temporality tags" do
      normal_dep = described_class.new("foo")
      build_dep = described_class.new("foo", [:build])
      run_dep = described_class.new("foo", [:run])

      deps = described_class.merge_repeats([normal_dep, build_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_a_build_dependency
      expect(deps.first).not_to be_a_runtime_dependency

      deps = described_class.merge_repeats([normal_dep, run_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_a_build_dependency
      expect(deps.first).not_to be_a_runtime_dependency

      deps = described_class.merge_repeats([build_dep, run_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_a_build_dependency
      expect(deps.first).not_to be_a_runtime_dependency
    end
  end

  it "finds closest spec to upgrade to" do
    dep = described_class.new("foo", [:build])
    f = formula("foo") { url "foo-1.0" }
    stub_formula_loader f
    allow(Formulary).to receive(:loader_for).with("homebrew/core/foo", from: :keg).and_return(double(get_formula: f))

    HOMEBREW_CELLAR.join("foo/1.0").mkpath
    compiler = DevelopmentTools.default_compiler
    stdlib = :libcxx
    tab = Tab.create(f, compiler, stdlib)
    tab.write

    expect(dep.closest_spec_for_dependency_upgrade_sym).to eq(:stable)
  end

  it "returns stable closest spec to upgrade to since taps differ" do
    dep = described_class.new("foo", [:build])
    f = formula("foo") do
      url "foo-1.0"
      version "1.0"
      devel do
        version "1.2"
      end
    end
    stub_formula_loader f
    f_tap = formula("foo") do
      url "foo-1.0"
    end
    allow(f_tap).to receive(:tap).and_return(Tap.fetch("user/repo"))
    allow(Formulary).to receive(:loader_for).with("user/repo/foo", from: :keg).and_return(double(get_formula: f_tap))

    HOMEBREW_CELLAR.join("foo/1.1").mkpath
    tab = Tab.empty
    tab.tabfile = HOMEBREW_CELLAR/"foo/1.1/INSTALL_RECEIPT.json"
    tab["source"]["tap"] = "user/repo"
    tab["spec"] = "devel"
    tab["versions"] = { "stable" => "1.0", "devel" => "1.1", "head" => "HEAD", "version_scheme" => 0 }
    tab.write

    expect(dep.closest_spec_for_dependency_upgrade_sym).to eq(:stable)
  end

  it "returns devel closest spec to upgrade" do
    dep = described_class.new("foo", [:build])
    f = formula("foo") do
      url "foo-1.0"
      version "1.0"
      devel do
        url "foo-1.2"
        version "1.2"
      end
    end
    stub_formula_loader f

    HOMEBREW_CELLAR.join("foo/1.1").mkpath
    tab = Tab.empty
    tab.tabfile = HOMEBREW_CELLAR/"foo/1.1/INSTALL_RECEIPT.json"
    tab["source"]["spec"] = "devel"
    tab["versions"] = { "stable" => "1.0", "devel" => "1.1", "head" => "HEAD", "version_scheme" => 0 }
    tab.write

    expect(dep.closest_spec_for_dependency_upgrade_sym).to eq(:devel)
  end

  specify "equality" do
    foo1 = described_class.new("foo")
    foo2 = described_class.new("foo")
    expect(foo1).to eq(foo2)
    expect(foo1).to eql(foo2)

    bar = described_class.new("bar")
    expect(foo1).not_to eq(bar)
    expect(foo1).not_to eql(bar)

    foo3 = described_class.new("foo", [:build])
    expect(foo1).not_to eq(foo3)
    expect(foo1).not_to eql(foo3)
  end
end

describe TapDependency do
  subject { described_class.new("foo/bar/dog") }

  specify "#tap" do
    expect(subject.tap).to eq(Tap.new("foo", "bar"))
  end

  specify "#option_names" do
    expect(subject.option_names).to eq(%w[dog])
  end
end
