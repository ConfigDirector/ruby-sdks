# frozen_string_literal: true

module ConfigDirector
  module OpenFeature
    module Internal
      module ResolutionDetailsByReason
        Reason = ::OpenFeature::SDK::Provider::Reason
        ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

        RESOLUTION_DETAILS_BY_REASON = {
          "found-match" => ->(evaluation) { served_value_resolution(evaluation, Reason::TARGETING_MATCH) },
          "rollout-skipped-no-identifier" => ->(evaluation) { served_value_resolution(evaluation, Reason::DEFAULT) },
          "value-missing" => lambda { |evaluation|
            ::OpenFeature::SDK::Provider::ResolutionDetails.new(value: evaluation.value, reason: Reason::DEFAULT)
          },
          "config-state-missing" => lambda { |evaluation|
            failed_resolution(
              evaluation, ErrorCode::FLAG_NOT_FOUND, "No config with the key '#{evaluation.key}' was found."
            )
          },
          "client-not-ready" => lambda { |evaluation|
            failed_resolution(
              evaluation, ErrorCode::PROVIDER_NOT_READY, "ConfigDirector has not delivered config state yet."
            )
          },
          "type-mismatch" => ->(evaluation) { type_mismatch_resolution(evaluation) },
          "invalid-number" => ->(evaluation) { type_mismatch_resolution(evaluation) },
          "invalid-json" => ->(evaluation) { type_mismatch_resolution(evaluation) },
          "invalid-boolean" => ->(evaluation) { type_mismatch_resolution(evaluation) }
        }.freeze

        private_constant :Reason, :ErrorCode, :RESOLUTION_DETAILS_BY_REASON

        def self.of_the_evaluation(evaluation)
          RESOLUTION_DETAILS_BY_REASON.fetch(evaluation.reason).call(evaluation)
        end

        def self.served_value_resolution(evaluation, reason)
          ::OpenFeature::SDK::Provider::ResolutionDetails.new(
            value: evaluation.value, reason: reason, variant: evaluation.variation&.name || evaluation.value_id
          )
        end

        def self.type_mismatch_resolution(evaluation)
          failed_resolution(
            evaluation, ErrorCode::TYPE_MISMATCH,
            "The value of '#{evaluation.key}' cannot be read as the requested type (#{evaluation.reason})."
          )
        end

        def self.failed_resolution(evaluation, error_code, error_message)
          ::OpenFeature::SDK::Provider::ResolutionDetails.new(
            value: evaluation.value, reason: Reason::ERROR, error_code: error_code, error_message: error_message
          )
        end

        private_class_method :served_value_resolution, :type_mismatch_resolution, :failed_resolution
      end
    end
  end
end
