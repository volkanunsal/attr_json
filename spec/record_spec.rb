require 'spec_helper'

RSpec.describe AttrJson::Record do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      self.table_name = "products"
      attr_json :str, :string
      attr_json :int, :integer
      attr_json :int_array, :integer, array: true
      attr_json :int_with_default, :integer, default: 5
    end
  end
  let(:instance) { klass.new }

  let(:custom_type) do
    Class.new(ActiveModel::Type::Value)
  end
  let(:klass_with_custom) do
    Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      self.table_name = "products"
      attr_json :custom, :type_raw
    end
  end
  let(:instance_custom) { klass_with_custom.new }

  [
    [:integer, 12, "12", 0],
    [:string, "12", 12, ""],
    [:decimal, BigDecimal("10.01"), "10.0100", 0],
    [:boolean, true, "t", false],
    [:date, Date.parse("2017-04-28"), "2017-04-28", nil],
    [:datetime, DateTime.parse("2017-04-04 04:45:00").to_time, "2017-04-04T04:45:00Z", nil],
    [:float, 45.45, "45.45", 0],
    [ActiveRecord::Type::Value.new, {"a" => {"b" => "c"}}, {"a" => {"b" => "c"}}, nil]
  ].each do |type, cast_value, uncast_value, falsey_value|
    describe "for primitive type #{type}" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include AttrJson::Record

          self.table_name = "products"
          attr_json :value, type
        end
      end
      it "properly saves good #{type}" do
        instance.value = cast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
      it "casts to #{type}" do
        instance.value = uncast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
      it "generates a query method #{type}?" do
        instance.value = cast_value
        expect(instance.value?).to be(true)
        instance.value = falsey_value
        expect(instance.value?).to be(false)
      end
    end
  end

  describe "for hash with ActiveRecord::Type::Value type instance" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record

        self.table_name = "products"
        attr_json :value, ActiveRecord::Type::Value.new
      end
    end

    it "stores the hash value directly without extra escaping" do
      value = {"a" => {"b" => "c"}}
      instance.value = value
      instance.save
      #load the instance directly from the database
      instance_loaded_raw = JSON.parse(ActiveRecord::Base.connection.execute(instance.class.all.to_sql).first["json_attributes"])
      expect(instance_loaded_raw["value"]).to eq(value)
    end
  end

  it "can set nil" do
    instance.str = nil
    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)

    instance.save!
    instance.reload

    expect(instance.str).to be_nil
    expect(instance.json_attributes).to eq("str" => nil, "int_with_default" => 5)
  end

  it "supports arrays" do
    instance.int_array = %w(1 2 3)
    expect(instance.int_array).to eq([1, 2, 3])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1, 2, 3])

    instance.int_array = 1
    expect(instance.int_array).to eq([1])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1])
  end

  it "has right ActiveRecord changed? even back and forth" do
    instance.str = "original"
    instance.save!

    expect(instance.changed?).to be(false)

    instance.str = "new"
    expect(instance.changed?).to be(true)
    expect(instance.json_attributes_changed?).to be(true)

    instance.str = "original"
    expect(instance.changed?).to be(false)
    expect(instance.json_attributes_changed?).to be(false)
  end

  it 'supports custom ActiveRecord registered types' do
    expect { instance_custom }.to raise_error ArgumentError

    ActiveRecord::Type.register(:type_raw, custom_type)
    expect { instance_custom }.to_not raise_error

    instance_custom.custom = 'foo'
    expect(instance_custom.json_attributes).to eq('custom' => 'foo')

    instance_custom.save!
    instance_custom.reload
    expect(instance_custom.custom).to eq 'foo'
  end

  # TODO: Should it LET you redefine instead, and spec for that? Have to pay
  # attention to store keys too if we let people replace attributes.
  it "raises on re-using attribute name" do
    expect {
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record

        self.table_name = "products"
        attr_json :value, :string
        attr_json :value, :integer
      end
    }.to raise_error(ArgumentError, /Can't add, conflict with existing attribute name `value`/)
  end

  it "can define without triggering a db connection" do
    expect(ActiveRecord::Base).not_to receive(:connection)

    Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      self.table_name = "products"
      attr_json :value, :string
    end
  end

  it "has registered attributes on registry" do
    expect(klass.attr_json_registry.attribute_names).to match([:str, :int, :int_array, :int_with_default])
  end

  context "initialize" do
    it "casts and fills in defaults" do
      o = klass.new(int: "12", str: 12, int_array: "12")

      expect(o.int).to eq 12
      expect(o.str).to eq "12"
      expect(o.int_array).to eq [12]
      expect(o.int_with_default).to eq 5
      expect(o.json_attributes).to eq('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "assign_attributes" do
    it "casts" do
      instance.assign_attributes(int: "12", str: 12, int_array: "12")

      expect(instance.int).to eq 12
      expect(instance.str).to eq "12"
      expect(instance.int_array).to eq [12]
      expect(instance.json_attributes).to include('int' => 12, 'str' => "12", 'int_array' => [12], 'int_with_default' => 5)
    end
  end

  context "defaults" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record

        self.table_name = "products"
        attr_json :str_with_default, :string, default: "DEFAULT_VALUE"
      end
    end

    it "supports defaults" do
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
    end

    it "saves default even without access" do
      instance.save!
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
      instance.reload
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
    end

    it "lets default override with nil" do
      instance.str_with_default = nil
      expect(instance.str_with_default).to eq(nil)
      instance.save
      instance.reload
      expect(instance.str_with_default).to eq(nil)
      expect(instance.json_attributes).to include("str_with_default" => nil)
    end
  end

  context "validation" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        include AttrJson::Record

        # validations need a model_name, which our anon class doens't have
        def self.model_name
          ActiveModel::Name.new(self, nil, "TestClass")
        end

        validates :str_array, presence: true
        validates :str,
          inclusion: {
            in: %w(small medium large),
            message: "%{value} is not a valid size"
          }

        attr_json :str, :string
        attr_json :str_array, :string, array: true
      end
    end

    it "has the usual validation errors" do
      instance.str = "nosize"
      expect(instance.save).to be false
      expect(instance.errors[:str_array]).to eq(["can't be blank"])
      expect(instance.errors[:str]).to eq(["nosize is not a valid size"])
    end
    it "saves with valid data" do
      instance.str = "small"
      instance.str_array = ["foo"]
      expect(instance.save).to be true
    end

  end

  context "store keys" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        include AttrJson::Record
        attr_json :value, :string, default: "DEFAULT_VALUE", store_key: :_store_key
      end
    end

    it "puts the default value in the jsonb hash at the given store key" do
      expect(instance.value).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE")
    end

    it "sets the value at the given store key" do
      instance.value = "set value"
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")

      instance.save!
      instance.reload

      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    it "takes from attribute name in new" do
      instance = klass.new(value: "set value")
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    it "takes from attribute name in assign_attributes" do
      instance.assign_attributes(value: "set value")
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    it "raises on conflicting store key" do
      expect {
        Class.new(ActiveRecord::Base) do
          include AttrJson::Record

          self.table_name = "products"
          attr_json :value, :string
          attr_json :other_thing, :string, store_key: "value"
        end
      }.to raise_error(ArgumentError, /Can't add, store key `value` conflicts with existing attribute/)
    end

    context "inheritance" do
      let(:subklass) do
        Class.new(klass) do
          self.table_name = "products"
          include AttrJson::Record
          attr_json :new_value, :integer, default: 10101, store_key: :_new_store_key
        end
      end
      let(:subklass_instance) { subklass.new }

      it "includes default values from the parent in the jsonb hash with the correct store keys" do
        expect(subklass_instance.value).to eq("DEFAULT_VALUE")
        expect(subklass_instance.new_value).to eq(10101)
        expect(subklass_instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE", "_new_store_key" => 10101)
      end
    end
  end



  # time-like objects get super weird on edge cases, so they get their own
  # spec context.
  context "time-like objects" do
    let(:zone_under_test) { "America/Chicago" }
    around do |example|
      orig_tz = ENV['TZ']
      ENV['TZ'] = zone_under_test
      example.run
      ENV['TZ'] = orig_tz
    end

    # Make sure it has non-zero usecs for our tests, and freeze it
    # to make sure code under test does not mutate it.
    let(:datetime_value) { DateTime.now.change(usec: 555555).freeze }
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record

        self.table_name = "products"
        attr_json :json_datetime, :datetime
        attr_json :json_time, :time
        attr_json :json_time_array, :time, array: true
        attr_json :json_datetime_array, :datetime, array: true
      end
    end

    context ":datetime type" do
      # 345123 to 345100
      def truncate_usec_to_ms(int)
        int.to_i / 1000 * 1000
      end

      before do
        instance.datetime_type = datetime_value
        instance.json_datetime = datetime_value
      end

      it "has the same microseconds on create" do
        # AR doesn't touch it in any way here, so we shouldn't either.
        expect(instance.json_datetime.usec).to eq(instance.datetime_type.usec)
      end

      it "rounds usec to ms after save" do
        instance.save!

        expect(instance.json_datetime.usec % 1000).to eq(0)

        expect(truncate_usec_to_ms(instance.json_datetime.usec)).to eq(truncate_usec_to_ms(instance.datetime_type.usec))
      end

      describe "a zoned time" do
        around do |example|
          original = ENV['TZ']
          ENV['TZ'] = 'America/New_York'
          example.run
          ENV['TZ'] = original
        end

        it "keeps the right moment in time even if not the timezone" do
          a_local_time = Time.local(2018,4,14,5,50,01)

          instance.json_datetime = a_local_time.dup
          instance.save

          expect(instance.json_datetime.getutc).to eq(a_local_time.getutc)
        end
      end

      describe "without .time_zone_aware_attributes" do
        around do |example|
          original = ActiveRecord::Base.time_zone_aware_attributes
          ActiveRecord::Base.time_zone_aware_attributes = false
          example.run
          ActiveRecord::Base.time_zone_aware_attributes = original
        end

        it "has the same class and zone on create" do
          # AR doesn't cast or transform in any way here, so we shouldn't either.
          expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)
        end

        it "has the same class and zone after save" do
          instance.save!

          expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)

          # It's actually a Time with zone UTC now, not a DateTime, don't REALLY
          # need to check for this, but if it changes AR may have changed enough
          # that we should pay attention -- failing here doesn't neccesarily
          # mean anything is wrong though, although we prob want OURs to be UTC.
          expect(instance.json_datetime.class).to eq(Time)
          expect(instance.json_datetime.zone).to eq("UTC")
        end

        it "has the same class and zone on fetch" do
          instance.save!

          new_instance = klass.find(instance.id)
          expect(new_instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(new_instance.json_datetime.zone).to eq(instance.datetime_type.zone)
        end

        it "to_json's before save same as raw ActiveRecord" do
          to_json = JSON.parse(instance.to_json)
          expect(to_json["json_attributes"]["json_datetime"]).to eq to_json["datetime_type"]
        end
      end

      # This is the default value, but we aren't playing quite right with it,
      # our date/time attributes do NOT at present use ActiveSupport::TimeWithZone,
      # like ordinary AR attributes. Not sure how big a problem this is, or if
      # it's getting timezones wrong.
      # See https://github.com/jrochkind/attr_json/issues/16
      describe "with .time_zone_aware_attributes" do
        before do
          skip "Not currently supporting :time_zone_aware_attributes in date/time json_attributes"
        end
        around do |example|
          original = ActiveRecord::Base.time_zone_aware_attributes
          ActiveRecord::Base.time_zone_aware_attributes = true
          example.run
          ActiveRecord::Base.time_zone_aware_attributes = original
        end

        it "has the same class and zone on create" do
          # AR doesn't cast or transform in any way here, so we shouldn't either.
          expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)
        end

        it "has the same class and zone after save" do
          instance.save!

          expect(instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(instance.json_datetime.zone).to eq(instance.datetime_type.zone)

          # It's actually a Time with zone UTC now, not a DateTime, don't REALLY
          # need to check for this, but if it changes AR may have changed enough
          # that we should pay attention -- failing here doesn't neccesarily
          # mean anything is wrong though, although we prob want OURs to be UTC.
          expect(instance.json_datetime.class).to eq(Time)
          expect(instance.json_datetime.zone).to eq("UTC")
        end

        it "has the same class and zone on fetch" do
          instance.save!

          new_instance = klass.find(instance.id)
          expect(new_instance.json_datetime.class).to eq(instance.datetime_type.class)
          expect(new_instance.json_datetime.zone).to eq(instance.datetime_type.zone)
        end

        it "to_json's before save same as raw ActiveRecord" do
          to_json = JSON.parse(instance.to_json)
          expect(to_json["json_attributes"]["json_datetime"]).to eq to_json["datetime_type"]
        end
      end

      describe "attributes_before_type_cast" do
        it "serializes as iso8601 in UTC with ms precision" do
          instance.json_datetime = datetime_value
          instance.save!

          json_serialized = JSON.parse(instance.json_attributes_before_type_cast)

          expect(json_serialized["json_datetime"]).to match(/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d.\d{3}Z/)
          expect(DateTime.iso8601(json_serialized["json_datetime"])).to eq(datetime_value.utc.change(usec: truncate_usec_to_ms(datetime_value.usec)))
        end
      end

      describe "to_json" do
        it "to_json's after save same as raw ActiveRecord" do
          instance.save!
          to_json = JSON.parse(instance.to_json)
          expect(to_json["json_attributes"]["json_datetime"]).to eq to_json["datetime_type"]
        end
      end
    end
  end

  context "specified container_attribute" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record
        self.table_name = "products"

        attr_json :value, :string, container_attribute: :other_attributes
      end
    end

    it "saves in appropriate place" do
      instance.value = "X"
      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank

      instance.save!
      instance.reload
      expect(instance.value).to eq("X")
      expect(instance.other_attributes).to eq("value" => "X")
      expect(instance.json_attributes).to be_blank

      instance.other_attributes = { value: "Y" }
      instance.save!
      instance.reload
      expect(instance.value).to eq("Y")
      expect(instance.other_attributes).to eq("value" => "Y")
      expect(instance.json_attributes).to be_blank

      instance.update!({ value: "Z" })
      instance.reload
      expect(instance.value).to eq("Z")
      expect(instance.other_attributes).to eq("value" => "Z")
      expect(instance.json_attributes).to be_blank

    end

    describe "change default container attribute" do
      shared_examples 'change_default_container' do
        it "saves in right place" do
          instance.value = "X"
          expect(instance.value).to eq("X")
          expect(instance.other_attributes).to eq("value" => "X")
          expect(instance.json_attributes).to be_blank

          instance.save!
          instance.reload
          expect(instance.value).to eq("X")
          expect(instance.other_attributes).to eq("value" => "X")
          expect(instance.json_attributes).to be_blank

          instance.other_attributes = { value: "Y" }
          instance.save!
          instance.reload
          expect(instance.value).to eq("Y")
          expect(instance.other_attributes).to eq("value" => "Y")
          expect(instance.json_attributes).to be_blank

          instance.update!({ value: "Z" })
          instance.reload
          expect(instance.value).to eq("Z")
          expect(instance.other_attributes).to eq("value" => "Z")
          expect(instance.json_attributes).to be_blank
        end
      end

      describe 'via AttrJson.config' do
        before do
          AttrJson.config do |c|
            c.merge(default_container_attribute: :other_attributes)
          end
        end
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include AttrJson::Record
            self.table_name = "products"
            attr_json :value, :string
          end
        end
        include_examples 'change_default_container'
      end

      describe 'via attr_json_config' do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include AttrJson::Record
            self.table_name = "products"
            self.attr_json_config(default_container_attribute: :other_attributes)
            attr_json :value, :string
          end
        end
        include_examples 'change_default_container'
      end
    end

    describe "multiple jsonb container attributes" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include AttrJson::Record
          self.table_name = "products"

          self.attr_json_config(default_container_attribute: :other_attributes)
          attr_json :foo, :string
          attr_json :bar, :string

          attr_json :value, :string, container_attribute: :json_attributes
          attr_json :value2, :string, container_attribute: :json_attributes
        end
      end

      it "saves in right place" do
        instance.value = "X"
        instance.value2 = "Y"
        expect(instance.value).to eq("X")
        expect(instance.value2).to eq("Y")
        expect(instance.json_attributes).to eq("value" => "X", "value2" => "Y")
        expect(instance.other_attributes).to be_blank

        instance.save!
        instance.reload
        expect(instance.value).to eq("X")
        expect(instance.value2).to eq("Y")
        expect(instance.json_attributes).to eq("value" => "X", "value2" => "Y")
        expect(instance.other_attributes).to be_blank

        instance.json_attributes = { value: "A", value2: "B" }
        instance.save!
        instance.reload
        expect(instance.value).to eq("A")
        expect(instance.value2).to eq("B")
        expect(instance.json_attributes).to eq("value" => "A", "value2" => "B")
        expect(instance.other_attributes).to be_blank

        instance.update!({ json_attributes: { value: "C", value2: "D" } })
        instance.reload
        expect(instance.value).to eq("C")
        expect(instance.value2).to eq("D")
        expect(instance.json_attributes).to eq("value" => "C", "value2" => "D")
        expect(instance.other_attributes).to be_blank

        instance.foo = "X"
        instance.bar = "Y"
        expect(instance.foo).to eq("X")
        expect(instance.bar).to eq("Y")
        expect(instance.json_attributes).to eq("value" => "C", "value2" => "D")
        expect(instance.other_attributes).to eq("foo" => "X", "bar" => "Y")

        instance.save!
        instance.reload
        expect(instance.foo).to eq("X")
        expect(instance.bar).to eq("Y")
        expect(instance.json_attributes).to eq("value" => "C", "value2" => "D")
        expect(instance.other_attributes).to eq("foo" => "X", "bar" => "Y")

        instance.other_attributes = { foo: "A", bar: "B" }
        instance.save!
        instance.reload
        expect(instance.foo).to eq("A")
        expect(instance.bar).to eq("B")
        expect(instance.json_attributes).to eq("value" => "C", "value2" => "D")
        expect(instance.other_attributes).to eq("foo" => "A", "bar" => "B")

        instance.update!({ json_attributes: { value: "K", value2: "L" }, other_attributes: { foo: "M", bar: "N"} })
        instance.reload
        expect(instance.foo).to eq("M")
        expect(instance.bar).to eq("N")
        expect(instance.value).to eq("K")
        expect(instance.value2).to eq("L")
        expect(instance.json_attributes).to eq("value" => "K", "value2" => "L")
        expect(instance.other_attributes).to eq("foo" => "M", "bar" => "N")
      end
    end

    describe "with store key" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include AttrJson::Record
          self.table_name = "products"

          attr_json :value, :string, store_key: "_store_key", container_attribute: :other_attributes
        end
      end

      it "saves with store_key" do
        instance.value = "X"
        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank

        instance.save!
        instance.reload

        expect(instance.value).to eq("X")
        expect(instance.other_attributes).to eq("_store_key" => "X")
        expect(instance.json_attributes).to be_blank
      end

      describe "multiple containers with same store key" do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include AttrJson::Record
            self.table_name = "products"

            attr_json :value, :string, store_key: "_store_key", container_attribute: :json_attributes
            attr_json :other_value, :string, store_key: "_store_key", container_attribute: :other_attributes
          end
        end
        it "is all good" do
          instance.value = "value"
          instance.other_value = "other_value"

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")

          instance.save!
          instance.reload

          expect(instance.value).to eq("value")
          expect(instance.json_attributes).to eq("_store_key" => "value")
          expect(instance.other_value).to eq("other_value")
          expect(instance.other_attributes).to eq("_store_key" => "other_value")
        end
        describe "with defaults" do
          let(:klass) do
            Class.new(ActiveRecord::Base) do
              include AttrJson::Record
              self.table_name = "products"

              attr_json :value, :string, default: "value default", store_key: "_store_key", container_attribute: :json_attributes
              attr_json :other_value, :string, default: "other value default", store_key: "_store_key", container_attribute: :other_attributes
            end
          end

          it "registers container as changed because of defaults" do
            # even though we made no changes, we want defaults to count as changes? We think?
            # https://github.com/jrochkind/attr_json/issues/26
            expect(instance.json_attributes_changed?).to be true
          end

          it "is all good" do
            expect(instance.value).to eq("value default")
            expect(instance.json_attributes).to eq("_store_key" => "value default")
            expect(instance.other_value).to eq("other value default")
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end

          it "fills default on direct set" do
            instance.json_attributes = {}
            expect(instance.json_attributes).to eq("_store_key" => "value default")

            instance.other_attributes = {}
            expect(instance.other_attributes).to eq("_store_key" => "other value default")
          end

          it "saves defaults when they are the only changes" do
            instance.save!
            # better way to get what's really in the db skipping model?
            saved_data = ActiveRecord::Base.connection.execute("select * from products where id = #{instance.id}").to_a.first
            expect(saved_data["json_attributes"]).to be_present
            expect(JSON.parse(saved_data["json_attributes"])).to eq("_store_key"=>"value default")
            expect(saved_data["other_attributes"]).to be_present
            expect(JSON.parse(saved_data["other_attributes"])).to eq("_store_key"=>"other value default")
          end
        end
      end
    end

    xdescribe "rails_attribute" do
      it "does not register rails attribute by default" do
        expect(instance.attributes.keys).not_to include("str")
      end
      describe "with rails_attribute: true" do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include AttrJson::Record

            self.table_name = "products"
            attr_json :str, :string, array: true, rails_attribute: true
          end
        end
        it "registers attribute and type" do
          expect(instance.attributes.keys).to include("str")
          expect(instance.type_for_attribute("str")).to be_kind_of(AttrJson::Type::Array)
          expect(instance.type_for_attribute("str").base_type).to be_kind_of(ActiveModel::Type::String)
        end
        it "still has our custom methods on top" do
          skip "gah, how do we test this"
        end
      end
    end
  end
end
