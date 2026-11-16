# frozen_string_literal: true

module ReadsDeclaredAsText
  def self.new_checkout_enabled(client)
    client.get_value("new-checkout", false)
  end

  def self.checkout_settings(client)
    client.get_value("checkout-settings", {})
  end

  def self.checkout_settings_with_symbol_keys(client)
    client.get_value("checkout-settings", { size: 1 })
  end

  def self.new_checkout_evaluated(client)
    client.evaluate("new-checkout", false).value
  end

  def self.watch_checkout_settings(client)
    client.watch("checkout-settings", {}) { |checkout_settings| print_text(checkout_settings) }
  end

  def self.print_text(text)
    puts text
  end
end
