# frozen_string_literal: true

require "cases/helper"
require "yaml"

class ErrorsTest < ActiveModel::TestCase
  class Person
    extend ActiveModel::Naming
    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    attr_accessor :name, :age
    attr_reader   :errors

    def validate!
      errors.add(:name, :blank, message: "cannot be nil") if name == nil
    end

    def read_attribute_for_validation(attr)
      send(attr)
    end

    def self.human_attribute_name(attr, options = {})
      attr
    end

    def self.lookup_ancestors
      [self]
    end
  end

  def test_delete
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name)
    errors.delete("name")
    assert_empty errors[:name]
  end

  def test_include?
    errors = ActiveModel::Errors.new(self)
    errors.add(:foo, "omg")
    assert_includes errors, :foo, "errors should include :foo"
    assert_includes errors, "foo", "errors should include 'foo' as :foo"
  end

  def test_dup
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name)
    errors_dup = errors.dup
    assert_not_same errors_dup.errors, errors.errors
  end

  def test_has_key?
    errors = ActiveModel::Errors.new(self)
    errors.add(:foo, "omg")
    assert_equal true, errors.has_key?(:foo), "errors should have key :foo"
    assert_equal true, errors.has_key?("foo"), "errors should have key 'foo' as :foo"
  end

  def test_has_no_key
    errors = ActiveModel::Errors.new(self)
    assert_equal false, errors.has_key?(:name), "errors should not have key :name"
  end

  def test_key?
    errors = ActiveModel::Errors.new(self)
    errors.add(:foo, "omg")
    assert_equal true, errors.key?(:foo), "errors should have key :foo"
    assert_equal true, errors.key?("foo"), "errors should have key 'foo' as :foo"
  end

  def test_no_key
    errors = ActiveModel::Errors.new(self)
    assert_equal false, errors.key?(:name), "errors should not have key :name"
  end

  test "clear errors" do
    person = Person.new
    person.validate!

    assert_equal 1, person.errors.count
    person.errors.clear
    assert_empty person.errors
  end

  test "error access is indifferent" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, "omg")

    assert_equal ["omg"], errors["name"]
  end

  test "values returns an array of messages" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, "omg")
    errors.add(:name, "zomg")

    assert_deprecated do
      assert_equal ["omg", "zomg"], errors.values
    end
  end

  test "values returns an empty array after try to get a message only" do
    errors = ActiveModel::Errors.new(self)
    errors.messages[:foo]
    errors.messages[:baz]

    assert_deprecated do
      assert_equal [], errors.values
    end
  end

  test "keys returns the error keys" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name)
    errors.add(:age)

    assert_deprecated do
      assert_equal [:name, :age], errors.keys
    end
  end

  test "keys returns an empty array after try to get a message only" do
    errors = ActiveModel::Errors.new(self)
    errors.messages[:foo]
    errors.messages[:baz]

    assert_deprecated do
      assert_equal [], errors.keys
    end
  end

  test "detecting whether there are errors with empty?, blank?, include?" do
    person = Person.new
    person.errors[:foo]
    assert_empty person.errors
    assert_predicate person.errors, :blank?
    assert_not_includes person.errors, :foo
  end

  test "include? does not add a key to messages hash" do
    person = Person.new
    person.errors.include?(:foo)

    assert_not person.errors.messages.key?(:foo)
  end

  test "adding errors using conditionals with Person#validate!" do
    person = Person.new
    person.validate!
    assert_equal ["name cannot be nil"], person.errors.full_messages
    assert person.errors.added?(:name, :blank)
  end

  test "add creates an error object and returns it" do
    person = Person.new
    error = person.errors.add(:name, :blank)

    assert_equal :name, error.attribute
    assert_equal :blank, error.type
    assert_equal error, person.errors.first
  end

  test "add, with type as symbol" do
    person = Person.new
    person.errors.add(:name, :blank)

    assert_equal :blank, person.errors.first.type
    assert_equal ["can't be blank"], person.errors[:name]
  end

  test "add, with type as String" do
    msg = "custom msg"

    person = Person.new
    person.errors.add(:name, msg)

    assert_equal :invalid, person.errors.first.type
    assert_equal [msg], person.errors[:name]
  end

  test "add, with type as nil" do
    person = Person.new
    person.errors.add(:name)

    assert_equal :invalid, person.errors.first.type
    assert_equal ["is invalid"], person.errors[:name]
  end

  test "add, with type as Proc, which evaluates to String" do
    msg = "custom msg"
    type = Proc.new { msg }

    person = Person.new
    person.errors.add(:name, type)

    assert_equal :invalid, person.errors.first.type
    assert_equal [msg], person.errors[:name]
  end

  test "add, type being Proc, which evaluates to Symbol" do
    type = Proc.new { :blank }

    person = Person.new
    person.errors.add(:name, type)

    assert_equal :blank, person.errors.first.type
    assert_equal ["can't be blank"], person.errors[:name]
  end

  test "initialize options[:message] as Proc, which evaluates to String" do
    msg = "custom msg"
    type = Proc.new { msg }

    person = Person.new
    person.errors.add(:name, :blank, message: type)

    assert_equal :blank, person.errors.first.type
    assert_equal [msg], person.errors[:name]
  end

  test "add, with options[:message] as Proc, which evaluates to String, where type is nil" do
    msg = "custom msg"
    type = Proc.new { msg }

    person = Person.new
    person.errors.add(:name, message: type)

    assert_equal :invalid, person.errors.first.type
    assert_equal [msg], person.errors[:name]
  end

  test "add, with options[:message] as Proc, which evaluates to Symbol, where type is nil" do
    type = Proc.new { :empty }

    person = Person.new
    person.errors.add(:name, message: type)

    assert_equal :empty, person.errors.first.type
    assert_equal ["can't be empty"], person.errors[:name]
  end

  test "added? detects indifferent if a specific error was added to the object" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert person.errors.added?(:name, "cannot be blank")
    assert person.errors.added?("name", "cannot be blank")
  end

  test "added? handles symbol message" do
    person = Person.new
    person.errors.add(:name, :blank)
    assert person.errors.added?(:name, :blank)
  end

  test "added? handles proc messages" do
    person = Person.new
    message = Proc.new { "cannot be blank" }
    person.errors.add(:name, message)
    assert person.errors.added?(:name, message)
  end

  test "added? defaults message to :invalid" do
    person = Person.new
    person.errors.add(:name)
    assert person.errors.added?(:name)
  end

  test "added? matches the given message when several errors are present for the same attribute" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    person.errors.add(:name, "is invalid")
    assert person.errors.added?(:name, "cannot be blank")
  end

  test "added? returns false when no errors are present" do
    person = Person.new
    assert_not person.errors.added?(:name)
  end

  test "added? returns false when checking a nonexisting error and other errors are present for the given attribute" do
    person = Person.new
    person.errors.add(:name, "is invalid")
    assert_not person.errors.added?(:name, "cannot be blank")
  end

  # TODO: check if this behavior change is ok
  test "added? returns true when checking for errors of one attribute, without providing message arguments" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert person.errors.added?(:name)
  end

  test "added? returns false when checking for an error by symbol and a different error with same message is present" do
    I18n.backend.store_translations("en", errors: { attributes: { name: { wrong: "is wrong", used: "is wrong" } } })
    person = Person.new
    person.errors.add(:name, :wrong)
    assert_not person.errors.added?(:name, :used)
  end

  test "size calculates the number of error messages" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert_equal 1, person.errors.size
  end

  test "count calculates the number of error messages" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert_equal 1, person.errors.count
  end

  test "to_a returns the list of errors with complete messages containing the attribute names" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    person.errors.add(:name, "cannot be nil")
    assert_equal ["name cannot be blank", "name cannot be nil"], person.errors.to_a
  end

  test "to_hash returns the error messages hash" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert_equal({ name: ["cannot be blank"] }, person.errors.to_hash)
  end

  test "to_hash returns a hash without default proc" do
    person = Person.new
    assert_nil person.errors.to_hash.default_proc
  end

  test "as_json returns a hash without default proc" do
    person = Person.new
    assert_nil person.errors.as_json.default_proc
  end

  test "full_messages creates a list of error messages with the attribute name included" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    person.errors.add(:name, "cannot be nil")
    assert_equal ["name cannot be blank", "name cannot be nil"], person.errors.full_messages
  end

  test "full_messages_for contains all the error messages for the given attribute indifferent" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    person.errors.add(:name, "cannot be nil")
    assert_equal ["name cannot be blank", "name cannot be nil"], person.errors.full_messages_for(:name)
  end

  test "full_messages_for does not contain error messages from other attributes" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    person.errors.add(:email, "cannot be blank")
    assert_equal ["name cannot be blank"], person.errors.full_messages_for(:name)
    assert_equal ["name cannot be blank"], person.errors.full_messages_for("name")
  end

  test "full_messages_for returns an empty list in case there are no errors for the given attribute" do
    person = Person.new
    person.errors.add(:name, "cannot be blank")
    assert_equal [], person.errors.full_messages_for(:email)
  end

  test "full_message returns the given message when attribute is :base" do
    person = Person.new
    assert_deprecated do
      assert_equal "press the button", person.errors.full_message(:base, "press the button")
    end
  end

  test "full_message returns the given message with the attribute name included" do
    person = Person.new
    assert_deprecated do
      assert_equal "name cannot be blank", person.errors.full_message(:name, "cannot be blank")
      assert_equal "name_test cannot be blank", person.errors.full_message(:name_test, "cannot be blank")
    end
  end

  test "as_json creates a json formatted representation of the errors hash" do
    person = Person.new
    person.validate!

    assert_equal({ name: ["cannot be nil"] }, person.errors.as_json)
  end

  test "as_json with :full_messages option creates a json formatted representation of the errors containing complete messages" do
    person = Person.new
    person.validate!

    assert_equal({ name: ["name cannot be nil"] }, person.errors.as_json(full_messages: true))
  end

  test "generate_message works without i18n_scope" do
    person = Person.new
    assert_not_respond_to Person, :i18n_scope
    assert_deprecated do
      assert_nothing_raised {
        person.errors.generate_message(:name, :blank)
      }
    end
  end

  test "details returns added error detail" do
    person = Person.new
    person.errors.add(:name, :invalid)
    assert_equal({ name: [{ error: :invalid }] }, person.errors.details)
  end

  test "details returns added error detail with custom option" do
    person = Person.new
    person.errors.add(:name, :greater_than, count: 5)
    assert_equal({ name: [{ error: :greater_than, count: 5 }] }, person.errors.details)
  end

  test "details do not include message option" do
    person = Person.new
    person.errors.add(:name, :invalid, message: "is bad")
    assert_equal({ name: [{ error: :invalid }] }, person.errors.details)
  end

  test "group_by_attribute" do
    person = Person.new
    error = person.errors.add(:name, :invalid, message: "is bad")
    hash = person.errors.group_by_attribute

    assert_equal({ name: [error] }, hash)
  end

  test "dup duplicates details" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)
    errors_dup = errors.dup
    errors_dup.add(:name, :taken)
    assert_not_equal errors_dup.details, errors.details
  end

  test "delete removes details on given attribute" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)
    errors.delete(:name)
    assert !errors.added?(:name)
  end

  test "delete returns the deleted messages" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)
    assert_equal ["is invalid"], errors.delete(:name)
  end

  test "clear removes details" do
    person = Person.new
    person.errors.add(:name, :invalid)

    assert_equal 1, person.errors.details.count
    person.errors.clear
    assert_empty person.errors.details
  end

  test "copy errors" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)
    person = Person.new
    person.errors.copy!(errors)

    assert person.errors.added?(:name, :invalid)
    person.errors.each do |error|
      assert_same person, error.base
    end
  end

  test "merge errors" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)

    person = Person.new
    person.errors.add(:name, :blank)
    person.errors.merge!(errors)

    assert(person.errors.added?(:name, :invalid))
    assert(person.errors.added?(:name, :blank))
  end

  test "errors are marshalable" do
    errors = ActiveModel::Errors.new(Person.new)
    errors.add(:name, :invalid)
    serialized = Marshal.load(Marshal.dump(errors))

    assert_equal Person, serialized.instance_variable_get(:@base).class
    assert_equal errors.messages, serialized.messages
    assert_equal errors.details, serialized.details
  end

  test "errors are compatible with marshal dumped from Rails 5.x" do
    # Derived from
    # errors = ActiveModel::Errors.new(Person.new)
    # errors.add(:name, :invalid)
    dump = "\x04\bU:\x18ActiveModel::Errors[\bo:\x17ErrorsTest::Person\x06:\f@errorsU;\x00[\b@\a{\x00{\x00{\x06:\tname[\x06I\"\x0Fis invalid\x06:\x06ET{\x06;\b[\x06{\x06:\nerror:\finvalid"
    serialized = Marshal.load(dump)

    assert_equal Person, serialized.instance_variable_get(:@base).class
    assert_equal({ name: ["is invalid"] }, serialized.messages)
    assert_equal({ name: [{ error: :invalid }] }, serialized.details)
  end

  test "errors are backward compatible with the Rails 4.2 format" do
    yaml = <<~CODE
    --- !ruby/object:ActiveModel::Errors
    base: &1 !ruby/object:ErrorsTest::Person
      errors: !ruby/object:ActiveModel::Errors
        base: *1
        messages: {}
    messages: {}
    CODE

    errors = YAML.load(yaml)
    errors.add(:name, :invalid)
    assert_equal({ name: ["is invalid"] }, errors.messages)
    assert_equal({ name: [{ error: :invalid }] }, errors.details)

    errors.clear
    assert_equal({}, errors.messages)
    assert_equal({}, errors.details)
  end

  test "errors are compatible with YAML dumped from Rails 5.x" do
    yaml = <<~CODE
    --- !ruby/object:ActiveModel::Errors
    base: &1 !ruby/object:ErrorsTest::Person
      errors: !ruby/object:ActiveModel::Errors
        base: *1
        messages: {}
        details: {}
    messages:
      :name:
      - is invalid
    details:
      :name:
      - :error: :invalid
    CODE

    errors = YAML.load(yaml)
    assert_equal({ name: ["is invalid"] }, errors.messages)
    assert_equal({ name: [{ error: :invalid }] }, errors.details)

    errors.clear
    assert_equal({}, errors.messages)
    assert_equal({}, errors.details)
  end

  test "errors are compatible with YAML dumped from Rails 6.x" do
    yaml = <<~CODE
    --- !ruby/object:ActiveModel::Errors
    base: &1 !ruby/object:ErrorsTest::Person
      errors: !ruby/object:ActiveModel::Errors
        base: *1
        errors: []
    errors:
    - !ruby/object:ActiveModel::Error
      base: *1
      attribute: :name
      type: :invalid
      options: {}
    CODE

    errors = YAML.load(yaml)
    assert_equal({ name: ["is invalid"] }, errors.messages)
    assert_equal({ name: [{ error: :invalid }] }, errors.details)

    errors.clear
    assert_equal({}, errors.messages)
    assert_equal({}, errors.details)
  end
end
