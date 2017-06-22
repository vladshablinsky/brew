require "dependable"
require "tab"

# A dependency on another Homebrew formula.
class Dependency
  extend Forwardable
  include Dependable

  attr_reader :name, :tags, :env_proc, :option_names

  DEFAULT_ENV_PROC = proc {}

  def initialize(name, tags = [], env_proc = DEFAULT_ENV_PROC, option_names = [name])
    @name = name
    @tags = tags
    @env_proc = env_proc
    @option_names = option_names
  end

  def to_s
    name
  end

  def ==(other)
    instance_of?(other.class) && name == other.name && tags == other.tags
  end
  alias eql? ==

  def hash
    name.hash ^ tags.hash
  end

  def tap
    CoreTap.instance
  end

  # The best spec we can upgrade the {Formula} to so it can satisfy dependency.
  def closest_spec_for_dependency_upgrade_sym
    rack = HOMEBREW_CELLAR.join(name.split("/").last)
    return :stable unless rack.exist?

    formula = Formulary.from_rack(rack)
    return :stable if formula.tap != tap

    active_spec_sym = formula.active_spec_sym
    return active_spec_sym if active_spec_sym == :stable

    installed_keg = formula.prefix
    return active_spec_sym unless installed_keg.join(Tab::FILENAME).exist?

    installed_tab = Tab.for_keg(installed_keg)
    return :stable if installed_tab.version_scheme < formula.version_scheme

    if active_spec_sym == :devel && formula.stable.version > installed_tab.devel_version
      return :stable
    end

    active_spec_sym
  end

  def use_closest_for_dependency_upgrade_spec!
    @spec = closest_spec_for_dependency_upgrade_sym
  end

  def use_spec!(spec)
    @spec = spec
  end

  def spec
    @spec || :stable
  end

  def to_formula
    formula = Formulary.factory(name, spec)
    formula.build = BuildOptions.new(options, formula.options)
    formula
  end

  delegate installed?: :to_formula

  def satisfied?(inherited_options)
    installed? && missing_options(inherited_options).empty?
  end

  def missing_options(inherited_options)
    formula = to_formula
    required = options
    required |= inherited_options
    required &= formula.options.to_a
    required -= Tab.for_formula(formula).used_options
    required
  end

  def modify_build_environment
    env_proc.call unless env_proc.nil?
  end

  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect}>"
  end

  # Define marshaling semantics because we cannot serialize @env_proc
  def _dump(*)
    Marshal.dump([name, tags])
  end

  def self._load(marshaled)
    new(*Marshal.load(marshaled))
  end

  class << self
    # Expand the dependencies of dependent recursively, optionally yielding
    # [dependent, dep] pairs to allow callers to apply arbitrary filters to
    # the list.
    # The default filter, which is applied when a block is not given, omits
    # optionals and recommendeds based on what the dependent has asked for.
    def expand(dependent, deps = dependent.deps, &block)
      # Keep track dependencies to avoid infinite cyclic dependency recursion.
      @expand_stack ||= []
      @expand_stack.push dependent.name

      expanded_deps = []

      deps.each do |dep|
        next if dependent.name == dep.name

        dep.use_closest_for_dependency_upgrade_spec!

        case action(dependent, dep, &block)
        when :prune
          next
        when :skip
          next if @expand_stack.include? dep.name
          expanded_deps.concat(expand(dep.to_formula, &block))
        when :keep_but_prune_recursive_deps
          expanded_deps << dep
        else
          next if @expand_stack.include? dep.name
          expanded_deps.concat(expand(dep.to_formula, &block))
          expanded_deps << dep
        end
      end

      merge_repeats(expanded_deps)
    ensure
      @expand_stack.pop
    end

    def action(dependent, dep, &_block)
      catch(:action) do
        if block_given?
          yield dependent, dep
        elsif dep.optional? || dep.recommended?
          prune unless dependent.build.with?(dep)
        end
      end
    end

    # Prune a dependency and its dependencies recursively
    def prune
      throw(:action, :prune)
    end

    # Prune a single dependency but do not prune its dependencies
    def skip
      throw(:action, :skip)
    end

    # Keep a dependency, but prune its dependencies
    def keep_but_prune_recursive_deps
      throw(:action, :keep_but_prune_recursive_deps)
    end

    def merge_repeats(all)
      grouped = all.group_by(&:name)

      all.map(&:name).uniq.map do |name|
        deps = grouped.fetch(name)
        dep  = deps.first
        tags = merge_tags(deps)
        option_names = deps.flat_map(&:option_names).uniq
        result = dep.class.new(name, tags, dep.env_proc, option_names)
        result.use_spec!(dep.spec)
        result
      end
    end

    private

    def merge_tags(deps)
      options = deps.flat_map(&:option_tags).uniq
      merge_necessity(deps) + merge_temporality(deps) + options
    end

    def merge_necessity(deps)
      # Cannot use `deps.any?(&:required?)` here due to its definition.
      if deps.any? { |dep| !dep.recommended? && !dep.optional? }
        [] # Means required dependency.
      elsif deps.any?(&:recommended?)
        [:recommended]
      else # deps.all?(&:optional?)
        [:optional]
      end
    end

    def merge_temporality(deps)
      if deps.all?(&:build?)
        [:build]
      elsif deps.all?(&:run?)
        [:run]
      else
        [] # Means both build and runtime dependency.
      end
    end
  end
end

class TapDependency < Dependency
  attr_reader :tap

  def initialize(name, tags = [], env_proc = DEFAULT_ENV_PROC, option_names = [name.split("/").last])
    @tap = Tap.fetch(name.rpartition("/").first)
    super(name, tags, env_proc, option_names)
  end

  def installed?
    super
  rescue FormulaUnavailableError
    false
  end
end
