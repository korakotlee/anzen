# Testing Anzen Gem with Rails

This guide provides step-by-step instructions to test the Anzen gem in a Rails application by creating a class with indirect recursion and verifying that it raises a `RecursionLimitExceeded` exception.

## Prerequisites

- Ruby installed (version compatible with Rails and Anzen)
- Rails installed (`gem install rails`)

## Steps

1. **Create a new Rails application:**

   ```bash
   rails new test_anzen
   ```

2. **Navigate to the project directory:**

   ```bash
   cd test_anzen
   ```

3. **Add the Anzen gem to the Gemfile:**

   Open `Gemfile` and add the following line (assuming the gem is local):

   ```ruby
   gem 'anzen'
   ```

4. **Install dependencies:**

   ```bash
   bundle install
   ```

5. **Configure Anzen:**

   Create a new initializer file `config/initializers/anzen.rb` with the following content to enable the recursion monitor:

   ```ruby
    require 'anzen'

    Anzen.setup(
      config: {
        enabled_monitors: ['recursion', 'memory'],
        monitors: {
          recursion: { depth_limit: 10 },
          memory: { limit_mb: 512, sampling_interval_ms: 100 }
        }
      }
    )
   ```

6. **Create a test model with indirect recursion:**

   Create a new file `app/models/test_model.rb` with the following content:

   ```ruby
   class TestModel
     def method_a
       method_b
     end

     def method_b
       method_a
     end
   end
   ```

7. **Start the Rails console:**

   ```bash
   rails console
   ```

8. **Test the recursion monitor:**

   In the Rails console, execute the following commands:

   ```ruby
   model = TestModel.new
   model.method_a
   ```

   This should raise an `Anzen::RecursionLimitExceeded` exception, indicating that the recursion monitor is working correctly.

## Expected Output

When calling `model.method_a`, you should see an error message similar to:

```
bundle exec rails c
Loading development environment (Rails 8.1.1)
test-anzen(dev):001> model = TestModel.new
test-anzen(dev):002>    model.method_a
app/models/test_model.rb:3:in 'TestModel#method_a': Recursion depth (11) exceeded threshold (10) (Anzen::RecursionLimitExceeded)
	from app/models/test_model.rb:7:in 'TestModel#method_b'
	from app/models/test_model.rb:3:in 'TestModel#method_a'
	from app/models/test_model.rb:7:in 'TestModel#method_b'
	from app/models/test_model.rb:3:in 'TestModel#method_a'
	from app/models/test_model.rb:7:in 'TestModel#method_b'
	from app/models/test_model.rb:3:in 'TestModel#method_a'
	from app/models/test_model.rb:7:in 'TestModel#method_b'
	from app/models/test_model.rb:3:in 'TestModel#method_a'
	from app/models/test_model.rb:7:in 'TestModel#method_b'
	from app/models/test_model.rb:3:in 'TestModel#method_a'
	from (test-anzen):2:in '<main>'
```

This confirms that the Anzen gem is successfully monitoring and preventing infinite recursion in your Rails application.

