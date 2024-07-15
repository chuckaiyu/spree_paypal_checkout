module SpreePaypalCheckout
  class Response
    attr_reader :params, :message, :test, :authorization, :avs_result, :cvv_result, :error_code, :emv_authorization, :network_transaction_id

    def success?
      @success
    end

    def failure?
      !success?
    end

    def initialize(success, message, params = {}, options = {})
      @success, @message, @params = success, message, params.stringify_keys
      @test = options[:test] || false
      @authorization = options[:authorization]
      @fraud_review = options[:fraud_review]
      @error_code = options[:error_code]
      @emv_authorization = options[:emv_authorization]
      @network_transaction_id = options[:network_transaction_id]

      @avs_result = if options[:avs_result].kind_of?(AVSResult)
                      options[:avs_result].to_hash
                    else
                      AVSResult.new(options[:avs_result]).to_hash
                    end

      @cvv_result = if options[:cvv_result].kind_of?(CVVResult)
                      options[:cvv_result].to_hash
                    else
                      CVVResult.new(options[:cvv_result]).to_hash
                    end
    end
  end
end