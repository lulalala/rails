# frozen_string_literal: true

require "active_support/core_ext/array/conversions"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/string/filters"
require "active_model/error"
require "active_model/nested_error"
require "forwardable"

module ActiveModel
  # == Active \Model \Errors
  #
  # Provides a modified +Hash+ that you can include in your object
  # for handling error messages and interacting with Action View helpers.
  #
  # A minimal implementation could be:
  #
  #   class Person
  #     # Required dependency for ActiveModel::Errors
  #     extend ActiveModel::Naming
  #
  #     def initialize
  #       @errors = ActiveModel::Errors.new(self)
  #     end
  #
  #     attr_accessor :name
  #     attr_reader   :errors
  #
  #     def validate!
  #       errors.add(:name, :blank, message: "cannot be nil") if name.nil?
  #     end
  #
  #     # The following methods are needed to be minimally implemented
  #
  #     def read_attribute_for_validation(attr)
  #       send(attr)
  #     end
  #
  #     def self.human_attribute_name(attr, options = {})
  #       attr
  #     end
  #
  #     def self.lookup_ancestors
  #       [self]
  #     end
  #   end
  #
  # The last three methods are required in your object for +Errors+ to be
  # able to generate error messages correctly and also handle multiple
  # languages. Of course, if you extend your object with <tt>ActiveModel::Translation</tt>
  # you will not need to implement the last two. Likewise, using
  # <tt>ActiveModel::Validations</tt> will handle the validation related methods
  # for you.
  #
  # The above allows you to do:
  #
  #   person = Person.new
  #   person.validate!            # => ["cannot be nil"]
  #   person.errors.full_messages # => ["name cannot be nil"]
  #   # etc..
  class Errors
    include Enumerable

    extend Forwardable
    def_delegators :@errors, :each, :size, :clear, :blank?, :empty?, *Enumerable.instance_methods(false)

    CALLBACKS_OPTIONS = [:if, :unless, :on, :allow_nil, :allow_blank, :strict]
    MESSAGE_OPTIONS = [:message]

    attr_reader :errors

    # Pass in the instance of the object that is using the errors object.
    #
    #   class Person
    #     def initialize
    #       @errors = ActiveModel::Errors.new(self)
    #     end
    #   end
    def initialize(base)
      @base = base
      @errors = []
    end

    def initialize_dup(other) # :nodoc:
      @errors = other.errors.deep_dup
      super
    end

    # Copies the errors from <tt>other</tt>.
    # For copying errors but keep <tt>@base</tt> as is.
    #
    # other - The ActiveModel::Errors instance.
    #
    # Examples
    #
    #   person.errors.copy!(other)
    def copy!(other) # :nodoc:
      @errors = other.errors.deep_dup
      @errors.each { |error|
        error.instance_variable_set("@base", @base)
      }
    end

    # Imports one error
    # Imported errors are wrapped as a NestedError,
    # providing access to original error object.
    # If attribute or type needs to be overriden, use `override_options`.
    #
    # override_options - Hash
    # @option override_options [Symbol] :attribute Override the attribute the error belongs to
    # @option override_options [Symbol] :type Override type of the error.
    def import(error, override_options = {})
      @errors.append(NestedError.new(@base, error, override_options))
    end

    # Merges the errors from <tt>other</tt>,
    # each <tt>Error</tt> wrapped as <tt>NestedError</tt>.
    #
    # other - The ActiveModel::Errors instance.
    #
    # Examples
    #
    #   person.errors.merge!(other)
    def merge!(other)
      other.errors.each { |error|
        import(error)
      }
    end

    # Search for errors matching +attribute+, +type+ or +options+.
    #
    # Only supplied params will be matched.
    #
    #   person.errors.where(:name) # => all name errors.
    #   person.errors.where(:name, :too_short) # => all name errors being too short
    #   person.errors.where(:name, :too_short, minimum: 2) # => all name errors being too short and minimum is 2
    def where(attribute, type = nil, **options)
      attribute, type, options = normalize_arguments(attribute, type, options)
      @errors.select {|error|
        error.match?(attribute, type, options)
      }
    end

    # Returns +true+ if the error messages include an error for the given key
    # +attribute+, +false+ otherwise.
    #
    #   person.errors.messages        # => {:name=>["cannot be nil"]}
    #   person.errors.include?(:name) # => true
    #   person.errors.include?(:age)  # => false
    def include?(attribute)
      @errors.any?{|error|
        error.match?(attribute.to_sym)
      }
    end

    # Delete messages for +key+. Returns the deleted messages.
    #
    #   person.errors[:name]        # => ["cannot be nil"]
    #   person.errors.delete(:name) # => ["cannot be nil"]
    #   person.errors[:name]        # => []
    def delete(attribute, type = nil, **options)
      attribute, type, options = normalize_arguments(attribute, type, options)
      @errors.delete_if do |error|
        error.match?(attribute, type, options)
      end
    end

    # When passed a symbol or a name of a method, returns an array of errors
    # for the method.
    #
    #   person.errors[:name]  # => ["cannot be nil"]
    #   person.errors['name'] # => ["cannot be nil"]
    def [](attribute)
      where(attribute.to_sym).map { |error| error.message }
    end

    # TODO: Maybe we can remove this?
    # Returns an xml formatted representation of the Errors hash.
    #
    #   person.errors.add(:name, :blank, message: "can't be blank")
    #   person.errors.add(:name, :not_specified, message: "must be specified")
    #   person.errors.to_xml
    #   # =>
    #   #  <?xml version=\"1.0\" encoding=\"UTF-8\"?>
    #   #  <errors>
    #   #    <error>name can't be blank</error>
    #   #    <error>name must be specified</error>
    #   #  </errors>
    def to_xml(options = {})
      to_a.to_xml({ root: "errors", skip_types: true }.merge!(options))
    end

    # Returns a Hash that can be used as the JSON representation for this
    # object. You can pass the <tt>:full_messages</tt> option. This determines
    # if the json object should contain full messages or not (false by default).
    #
    #   person.errors.as_json                      # => {:name=>["cannot be nil"]}
    #   person.errors.as_json(full_messages: true) # => {:name=>["name cannot be nil"]}
    def as_json(options = nil)
      to_hash(options && options[:full_messages])
    end

    # Returns a Hash of attributes with their error messages. If +full_messages+
    # is +true+, it will contain full messages (see +full_message+).
    #
    #   person.errors.to_hash       # => {:name=>["cannot be nil"]}
    #   person.errors.to_hash(true) # => {:name=>["name cannot be nil"]}
    def to_hash(full_messages = false)
      hash = {}
      @errors.each do |error|
        if full_messages
          message = error.full_message
        else
          message = error.message
        end

        if hash.has_key?(error.attribute)
          hash[error.attribute] << message
        else
          hash[error.attribute] = [message]
        end
      end
      hash
    end

    # Adds +message+ to the error messages and used validator type to +details+ on +attribute+.
    # More than one error can be added to the same +attribute+.
    # If no +message+ is supplied, <tt>:invalid</tt> is assumed.
    #
    #   person.errors.add(:name)
    #   # => ["is invalid"]
    #   person.errors.add(:name, :not_implemented, message: "must be implemented")
    #   # => ["is invalid", "must be implemented"]
    #
    #   person.errors.messages
    #   # => {:name=>["is invalid", "must be implemented"]}
    #
    #   person.errors.details
    #   # => {:name=>[{error: :not_implemented}, {error: :invalid}]}
    #
    # If +message+ is a symbol, it will be translated using the appropriate
    # scope (see +generate_message+).
    #
    # If +message+ is a proc, it will be called, allowing for things like
    # <tt>Time.now</tt> to be used within an error.
    #
    # If the <tt>:strict</tt> option is set to +true+, it will raise
    # ActiveModel::StrictValidationFailed instead of adding the error.
    # <tt>:strict</tt> option can also be set to any other exception.
    #
    #   person.errors.add(:name, :invalid, strict: true)
    #   # => ActiveModel::StrictValidationFailed: Name is invalid
    #   person.errors.add(:name, :invalid, strict: NameIsInvalid)
    #   # => NameIsInvalid: Name is invalid
    #
    #   person.errors.messages # => {}
    #
    # +attribute+ should be set to <tt>:base</tt> if the error is not
    # directly associated with a single attribute.
    #
    #   person.errors.add(:base, :name_or_email_blank,
    #     message: "either name or email must be present")
    #   person.errors.messages
    #   # => {:base=>["either name or email must be present"]}
    #   person.errors.details
    #   # => {:base=>[{error: :name_or_email_blank}]}
    def add(attribute, type = nil, **options)
      @errors.append(
        Error.new(
          @base,
          *normalize_arguments(attribute, type, options)
        )
      )
    end

    # Returns +true+ if an error on the attribute with the given message is
    # present, or +false+ otherwise. +message+ is treated the same as for +add+.
    #
    #   person.errors.add :name, :blank
    #   person.errors.added? :name, :blank           # => true
    #   person.errors.added? :name, "can't be blank" # => true
    #
    # If the error message requires an option, then it returns +true+ with
    # the correct option, or +false+ with an incorrect or missing option.
    #
    #  person.errors.add :name, :too_long, { count: 25 }
    #  person.errors.added? :name, :too_long, count: 25                     # => true
    #  person.errors.added? :name, "is too long (maximum is 25 characters)" # => true
    #  person.errors.added? :name, :too_long, count: 24                     # => false
    #  person.errors.added? :name, :too_long                                # => false
    #  person.errors.added? :name, "is too long"                            # => false
    def added?(attribute, type = nil, options = {})
      attribute, type, options = normalize_arguments(attribute, type, options)
      @errors.any?{|error|
        error.match?(attribute, type, options)
      }
    end

    # Returns all the full error messages in an array.
    #
    #   class Person
    #     validates_presence_of :name, :address, :email
    #     validates_length_of :name, in: 5..30
    #   end
    #
    #   person = Person.create(address: '123 First St.')
    #   person.errors.full_messages
    #   # => ["Name is too short (minimum is 5 characters)", "Name can't be blank", "Email can't be blank"]
    def full_messages
      @errors.map(&:full_message)
    end
    alias :to_a :full_messages

    # Returns all the full error messages for a given attribute in an array.
    #
    #   class Person
    #     validates_presence_of :name, :email
    #     validates_length_of :name, in: 5..30
    #   end
    #
    #   person = Person.create()
    #   person.errors.full_messages_for(:name)
    #   # => ["Name is too short (minimum is 5 characters)", "Name can't be blank"]
    def full_messages_for(attribute)
      where(attribute).map(&:full_message)
    end

    def marshal_dump # :nodoc:
      # TODO: Should this work for past serialized results?
      [@base, without_default_proc(@messages), without_default_proc(@details)]
    end

    def marshal_load(array) # :nodoc:
      # TODO: Should this work for past serialized results?
      @base, @messages, @details = array
      apply_default_array(@messages)
      apply_default_array(@details)
    end

  private

    def without_default_proc(hash)
      hash.dup.tap do |new_h|
        new_h.default_proc = nil
      end
    end

    def apply_default_array(hash)
      hash.default_proc = proc { |h, key| h[key] = [] }
      hash
    end

    # Error type can appear as <tt>type</tt> or <tt>options[:message]</tt>.
    # Message or type can also be dynamic.
    # This method evaluates them and normalize type/message to the appropriate place.
    def normalize_arguments(attribute, type, **options)
      # Evaluate proc first
      if type.respond_to?(:call)
        type = type.call(@base, options)
      end
      if options[:message].respond_to?(:call)
        options[:message] = options[:message].call(@base, options)
      end

      normalized_type = nil

      # Determine type from `type` or `options`
      if type.is_a?(Symbol)
        normalized_type = type
      else
        if options[:message].is_a?(Symbol)
          normalized_type = options.delete(:message)
        end

        if type.is_a? String
          options[:message] = type
        end
      end

      if normalized_type
        normalized_type = normalized_type.to_sym
      end

      [attribute.to_sym, normalized_type, options]
    end
  end

  # Raised when a validation cannot be corrected by end users and are considered
  # exceptional.
  #
  #   class Person
  #     include ActiveModel::Validations
  #
  #     attr_accessor :name
  #
  #     validates_presence_of :name, strict: true
  #   end
  #
  #   person = Person.new
  #   person.name = nil
  #   person.valid?
  #   # => ActiveModel::StrictValidationFailed: Name can't be blank
  class StrictValidationFailed < StandardError
  end

  # Raised when attribute values are out of range.
  class RangeError < ::RangeError
  end

  # Raised when unknown attributes are supplied via mass assignment.
  #
  #   class Person
  #     include ActiveModel::AttributeAssignment
  #     include ActiveModel::Validations
  #   end
  #
  #   person = Person.new
  #   person.assign_attributes(name: 'Gorby')
  #   # => ActiveModel::UnknownAttributeError: unknown attribute 'name' for Person.
  class UnknownAttributeError < NoMethodError
    attr_reader :record, :attribute

    def initialize(record, attribute)
      @record = record
      @attribute = attribute
      super("unknown attribute '#{attribute}' for #{@record.class}.")
    end
  end
end
