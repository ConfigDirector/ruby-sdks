# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Evaluation
      EvaluationContext = Data.define(:identifier, :kind, :name, :traits, :app_name, :app_version)

      class EvaluationContext
        USER_CONTEXT_KIND = "user"

        def effective_kind
          kind || USER_CONTEXT_KIND
        end
      end
    end
  end
end
