# frozen_string_literal: true

require "json"

module ConfigDirector
  module Internal
    module Connection
      module OfflineValuesFile
        def self.values_in(path)
          document = document_in(text_of(path), path)
          return document if document.is_a?(Hash)

          raise ConfigDirectorInitializationError,
                "The offline values file '#{path}' must hold a JSON object with one value per config key, " \
                "but holds #{description_of(document)}."
        end

        def self.text_of(path)
          File.open(path, "r:UTF-8", &:read)
        rescue SystemCallError, IOError, ArgumentError => e
          raise ConfigDirectorInitializationError, "The offline values file '#{path}' could not be read: #{e.message}"
        end

        def self.document_in(text, path)
          unless text.valid_encoding?
            raise ConfigDirectorInitializationError,
                  "The offline values file '#{path}' is not valid JSON: the text is not valid UTF-8."
          end

          JSON.parse(text, allow_duplicate_key: true)
        rescue JSON::ParserError => e
          raise ConfigDirectorInitializationError, "The offline values file '#{path}' is not valid JSON: #{e.message}"
        end

        def self.description_of(document)
          case document
          when nil then "null"
          when Array then "an array"
          when String then "a string"
          when true, false then "a boolean"
          else "a number"
          end
        end

        private_class_method :text_of, :document_in, :description_of
      end
    end
  end
end
