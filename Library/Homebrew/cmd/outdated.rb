#:  * `outdated` [`--quiet`|`--verbose`|`--json=v1`]:
#:    Show formulae that have an updated version available.
#:
#:    By default, version information is displayed in interactive shells, and
#:    suppressed otherwise.
#:
#:    If `--quiet` is passed, list only the names of outdated brews (takes
#:    precedence over `--verbose`).
#:
#:    If `--verbose` is passed, display detailed version information.
#:
#:    If `--json=`<version> is passed, the output will be in JSON format. The only
#:    valid version is `v1`.

require "formula"
require "keg"

module Homebrew
  def outdated
    formulae = ARGV.resolved_formulae.any? ? ARGV.resolved_formulae : Formula.installed
    if ARGV.json == "v1"
      outdated = print_outdated_json(formulae)
    else
      outdated = print_outdated(formulae)
    end
    Homebrew.failed = ARGV.resolved_formulae.any? && outdated.any?
  end

  def print_outdated(formulae)
    verbose = ($stdout.tty? || ARGV.verbose?) && !ARGV.flag?("--quiet")
    fetch_head = ARGV.fetch_head?

    formulae.select do |f|
      f.outdated?(:fetch_head => fetch_head)
    end.each do |f|
      if verbose
        outdated_versions = f.outdated_versions(:fetch_head => fetch_head)
        if outdated_versions.any? && f.head? && !fetch_head
          puts "#{f.full_name} (#{outdated_versions*", "}) HEAD update available"
        else
          puts "#{f.full_name} (#{outdated_versions*", "}) < #{f.pkg_version}"
        end
      else
        puts f.full_name
      end
    end
  end

  def print_outdated_json(formulae)
    json = []
    outdated = formulae.select(&:outdated?).each do |f|

      json << { :name => f.full_name,
                :installed_versions => f.outdated_versions.collect(&:to_s),
                :current_version => f.pkg_version.to_s }
    end
    puts Utils::JSON.dump(json)

    outdated
  end
end
