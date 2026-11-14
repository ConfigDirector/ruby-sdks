# frozen_string_literal: true

module ConfigDirector
  # The user or other entity, such as a device or an organization, that a config is evaluated for. A context
  # cannot be changed once built, and two contexts built with the same values are equal.
  class Context
    include Internal::ComparedByValue

    # @return [String, nil] the context's identifier
    attr_reader :id

    # @return [String, nil] the kind of entity the context represents, or +nil+ for +"user"+
    attr_reader :kind

    # @return [String, nil] the context's display name
    attr_reader :name

    # @return [Hash, nil] the context's traits, with every Symbol key and value read as its text
    attr_reader :traits

    # @param id [String, Integer, nil] the context's identifier, which should identify the user or other
    #   entity among contexts of the same kind. An Integer, such as the ID of a database record, is read as
    #   its digits. A percentage rollout places a context in a share by its +id+, so a context without one
    #   skips percentage rollouts.
    # @param kind [String, nil] the kind of entity the context represents, such as +"device"+,
    #   +"organization"+ or +"tenant"+. Leaving it out means +"user"+. A kind has 1 to 64 characters, using
    #   only lowercase letters (+a+ to +z+), digits, +-+ and +_+. Building a context never fails because of
    #   its kind: when the kind is invalid, the SDK ignores the whole context, evaluates as if no context
    #   was given and logs an error.
    # @param name [String, nil] the context's display name, shown in the ConfigDirector dashboard
    # @param traits [Hash, nil] any traits of the context, shown in the ConfigDirector dashboard. Targeting
    #   rules can use them. A Symbol key or value is read as its text, so +{ plan: :pro }+ is the trait
    #   +"plan"+ with the value +"pro"+.
    # @param anonymous [Boolean] whether the context is anonymous. An anonymous context is used to evaluate
    #   targeting rules, is not kept and does not appear in the dashboard.
    # @raise [ConfigDirectorValidationError] when +id+ is not a String or an Integer, +name+ is not a
    #   String, +traits+ is not a Hash, or +anonymous+ is neither +true+ nor +false+
    def initialize(id: nil, kind: nil, name: nil, traits: nil, anonymous: false)
      @id = Internal::Client::ContextAttributes.identifier_text(id)
      @kind = Internal::UnchangeableCopy.of(kind)
      @name = Internal::Client::ContextAttributes.name_text(name)
      @traits = Internal::Client::ContextAttributes.traits_with_symbols_as_text(traits)
      @anonymous = Internal::Client::ContextAttributes.anonymous_flag(anonymous)
      freeze
    end

    # @return [Boolean] whether the context is anonymous
    def anonymous?
      @anonymous
    end
  end
end
