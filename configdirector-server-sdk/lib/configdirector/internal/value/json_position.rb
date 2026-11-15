# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Value
      JsonPosition = Data.define(:config_key, :path, :nesting)

      class JsonPosition
        def self.at_the_top_of(config_key)
          new(config_key: config_key, path: "", nesting: 1)
        end

        def of_member(key_text)
          JsonPosition.new(
            config_key: config_key, path: path.empty? ? key_text : "#{path}.#{key_text}", nesting: nesting + 1
          )
        end

        def of_element(index)
          JsonPosition.new(config_key: config_key, path: "#{path}[#{index}]", nesting: nesting + 1)
        end

        def unservable_because(problem)
          UnservableValue.new("Invalid value for '#{config_key}'#{" at '#{path}'" unless path.empty?}: #{problem}")
        end
      end
    end
  end
end
