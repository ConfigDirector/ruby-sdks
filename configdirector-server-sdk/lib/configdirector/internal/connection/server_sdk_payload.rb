# frozen_string_literal: true

module ConfigDirector
  module Internal
    module Connection
      ServerSdkPayload = Data.define(:delta, :configs, :segments, :unreadable_configs, :unreadable_segments)

      class ServerSdkPayload
        def self.without_definitions
          of_definitions({})
        end

        def self.of_definitions(configs)
          new(delta: false, configs: configs, segments: {}, unreadable_configs: {}, unreadable_segments: {})
        end

        def configs_held_after(held_configs)
          delta ? held_configs.except(*unreadable_configs.keys).merge(configs) : configs
        end

        def segments_held_after(held_segments)
          delta ? held_segments.except(*unreadable_segments.keys).merge(segments) : segments
        end

        def segment_ids
          segments.keys + unreadable_segments.keys
        end
      end
    end
  end
end
