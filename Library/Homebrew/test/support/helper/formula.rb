require "formulary"

module Test
  module Helper
    module Formula
      def formula(name = "formula_name", path: Formulary.core_path(name), spec: :stable, alias_path: nil, &block)
        Class.new(::Formula, &block).new(name, path, spec, alias_path: alias_path)
      end

      # Use a stubbed {Formulary::FormulaLoader} to make a given formula be found
      # when loading from {Formulary} with `ref`.
      def stub_formula_loader(formula, ref = formula.full_name)
        loader = double
        allow(loader).to receive(:get_formula).and_return(formula)

        allow(loader).to receive(:get_formula).with(:stable, alias_path: anything) do
          begin
            formula.active_spec = :stable
          rescue FormulaSpecificationError
            nil
          end
        end.and_return(formula)

        allow(loader).to receive(:get_formula).with(:devel, alias_path: anything) do
          begin
            formula.active_spec = :devel
          rescue FormulaSpecificationError
            nil
          end
        end.and_return(formula)

        allow(loader).to receive(:get_formula).with(:head, alias_path: anything) do
          begin
            formula.active_spec = :head
          rescue FormulaSpecificationError
            nil
          end
        end.and_return(formula)
        allow(Formulary).to receive(:loader_for).with(ref, from: :keg).and_return(loader)
        allow(Formulary).to receive(:loader_for).with(ref, from: nil).and_return(loader)
        allow(Formulary).to receive(:loader_for).with(ref, from: :rack).and_return(loader)
      end
    end
  end
end
