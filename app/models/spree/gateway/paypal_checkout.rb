module Spree
  class Gateway::PaypalCheckout < Gateway
    preference :api_key, :string
    preference :secret_key, :string
    preference :server, :string, default: "api-m.sandbox.paypal.com"

    def authorize(_amount_in_cents, source, _gateway_options)
      response = parse_response(authorize_order(source.order_id))

      if response["status"] == "COMPLETED"
        authorization = response.dig("purchase_units", 0, "payments", "authorizations", 0) || {}

        source.update(
          order_status: response["status"], 
          authorization_id: authorization["id"], 
          authorization_status: authorization["status"], 
          authentication_expiration_time: authorization["expiration_time"]
        )

        SpreePaypalCheckout::Response.new(true, "Authorize order completed", {}, authorization: authorization["id"])
      else
        SpreePaypalCheckout::Response.new(false, response["message"], {}, error_code: response["debug_id"])
      end
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def capture(_amount_in_cents, authorization_id, _gateway_options)
      order = PaypalCheckoutOrder.find_by_authorization_id(authorization_id)

      if order.authentication_expiration_at && Time.now > order.authentication_expiration_at
        return SpreePaypalCheckout::Response.new(false, "Capture payment authentication expired")
      elsif Time.now > order.created_at.next_day(3)
        response = parse_response(reauthorize_payment(authorization_id))

        if response["status"] == "CREATED"
          authorization_id = response["id"]
        else
          return SpreePaypalCheckout::Response.new(false, response["message"], {}, error_code: response["debug_id"])
        end
      end

      capture_response = parse_response(capture_payment(authorization_id))

      if capture_response["status"] == "COMPLETED"
        order.update(
          authorization_status: capture_response["status"], 
          capture_id: capture_response["id"], 
          capture_status: capture_response["status"]
        )

        SpreePaypalCheckout::Response.new(true, "Capture payment completed", {}, authorization: capture_response["id"])
      else
        SpreePaypalCheckout::Response.new(false, capture_response["message"], {}, error_code: capture_response["debug_id"])
      end
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def purchase(_amount_in_cents, source, _gateway_options)
      response = parse_response(capture_order(source.order_id))

      if response["status"] == "COMPLETED"
        capture = response.dig("purchase_units", 0, "payments", "captures", 0) || {}

        source.update(
          order_status: response["status"], 
          capture_id: capture["id"], 
          capture_status: capture["status"]
        )

        SpreePaypalCheckout::Response.new(true, "Purchase order completed", {}, authorization: capture["id"])
      else
        SpreePaypalCheckout::Response.new(false, response["message"], {}, error_code: response["debug_id"])
      end
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def credit(amount_in_cents, capture_id, gateway_options)
      originator = gateway_options[:originator]

      if originator.present?
        response = parse_response(refund_payment(capture_id, refund_request_body(amount_in_cents, originator)))

        if response["status"] == "COMPLETED"
          order = PaypalCheckoutOrder.find_by_capture_id(capture_id)
          order.update(refunds: order.refunds.push({ refund_id: response["id"], refund_status: response["status"] }))
  
          SpreePaypalCheckout::Response.new(true, "Refund payment completed", {}, authorization: response["id"])
        else
          SpreePaypalCheckout::Response.new(false, response["message"], {}, error_code: response["debug_id"])
        end
      else
        SpreePaypalCheckout::Response.new(false, "Missing originator")
      end
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def void(authorization_id, _gateway_options)
      http_response = void_payment(authorization_id)

      if http_response.code == '204'
        order = PaypalCheckoutOrder.find_by_authorization_id(authorization_id)
        order.update(authorization_status: 'VOIDED')

        SpreePaypalCheckout::Response.new(true, "Void payment completed", {}, authorization: authorization_id)
      else
        SpreePaypalCheckout::Response.new(false, "Invalid http code #{http_response.code}")
      end
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def cancel(_response_code, payment = nil)
      if payment && payment.credit_allowed > 0
        payment.refunds.create(amount: payment.credit_allowed, reason: RefundReason.return_processing_reason)
      end
        
      SpreePaypalCheckout::Response.new(true, 'Payment all refunded')
    rescue Exception => e
      SpreePaypalCheckout::Response.new(false, e.message)
    end

    def payment_profiles_supported?
      false
    end

    def payment_source_class
      PaypalCheckoutOrder
    end

    def method_type
      "paypal_checkout"
    end

    def provider_class
      self.class
    end

    def intent
      auto_capture? ? "CAPTURE" : "AUTHORIZE"
    end

    def create_order(body)
      parse_response(post_request(api_url("v2/checkout/orders"), body))
    end

    private

    def authorize_order(order_id)
      post_request(api_url("v2/checkout/orders/#{order_id}/authorize"))
    end

    def capture_order(order_id)
      post_request(api_url("v2/checkout/orders/#{order_id}/capture"))
    end

    def reauthorize_payment(authorization_id)
      post_request(api_url("v2/payments/authorizations/#{authorization_id}/reauthorize"))
    end

    def capture_payment(authorization_id)
      post_request(api_url("v2/payments/authorizations/#{authorization_id}/capture"))
    end

    def refund_payment(capture_id, body)
      post_request(api_url("v2/payments/captures/#{capture_id}/refund"), body)
    end

    def void_payment(authorization_id)
      post_request(api_url("v2/payments/authorizations/#{authorization_id}/void"))
    end

    def refund_request_body(amount_in_cents, originator)
      {
        amount: {
          value: (amount_in_cents * 0.01).round(2),
          currency_code: originator&.money&.currency&.iso_code
        },
        note_to_payer: originator&.reason&.name
      }
    end

    def api_url(url)
      URI.parse("https://#{preferred_server}/#{url}")
    end

    def generate_access_token
      response = parse_response(post_request_without_token(api_url("v1/oauth2/token")))
      response["access_token"]
    end

    def execute_api(request:, body:, uri:)
      request.content_type = "application/json"
      request_options = { use_ssl: uri.scheme == "https" }

      response = Net::HTTP.start(uri.hostname, uri.port, request_options) do |http|
        response = http.request(request)
      end

      response
    end

    def post_request(uri, body = {})
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{generate_access_token}"
      request.body = body.to_json if body.present?

      execute_api(request: request, body: body, uri: uri)
    end

    def post_request_without_token(uri, body = {})
      request = Net::HTTP::Post.new(uri)
      request.basic_auth("#{preferred_api_key}", "#{preferred_secret_key}")
      request.body = "grant_type=client_credentials"

      execute_api(request: request, body: body, uri: uri)
    end

    def parse_response(response)
      JSON.parse(response.read_body) rescue response
    end
  end
end