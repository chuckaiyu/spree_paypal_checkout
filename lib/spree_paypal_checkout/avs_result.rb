module SpreePaypalCheckout
  class AVSResult
    MESSAGES = {
      'A' => 'Street address matches, but postal code does not match.',
      'B' => 'Street address matches, but postal code not verified.',
      'C' => 'Street address and postal code do not match.',
      'D' => 'Street address and postal code match.',
      'E' => 'AVS data is invalid or AVS is not allowed for this card type.',
      'F' => 'Card member\'s name does not match, but billing postal code matches.',
      'G' => 'Non-U.S. issuing bank does not support AVS.',
      'H' => 'Card member\'s name does not match. Street address and postal code match.',
      'I' => 'Address not verified.',
      'J' => 'Card member\'s name, billing address, and postal code match. Shipping information verified and chargeback protection guaranteed through the Fraud Protection Program.',
      'K' => 'Card member\'s name matches but billing address and billing postal code do not match.',
      'L' => 'Card member\'s name and billing postal code match, but billing address does not match.',
      'M' => 'Street address and postal code match.',
      'N' => 'Street address and postal code do not match. For American Express: Card member\'s name, street address and postal code do not match.',
      'O' => 'Card member\'s name and billing address match, but billing postal code does not match.',
      'P' => 'Postal code matches, but street address not verified.',
      'Q' => 'Card member\'s name, billing address, and postal code match. Shipping information verified but chargeback protection not guaranteed.',
      'R' => 'System unavailable.',
      'S' => 'U.S.-issuing bank does not support AVS.',
      'T' => 'Card member\'s name does not match, but street address matches.',
      'U' => 'Address information unavailable.',
      'V' => 'Card member\'s name, billing address, and billing postal code match.',
      'W' => 'Street address does not match, but 9-digit postal code matches.',
      'X' => 'Street address and 9-digit postal code match.',
      'Y' => 'Street address and 5-digit postal code match.',
      'Z' => 'Street address does not match, but 5-digit postal code matches.'
    }

    # Map vendor's AVS result code to a postal match code
    POSTAL_MATCH_CODE = {
      'Y' => %w(D H F H J L M P Q V W X Y Z),
      'N' => %w(A C K N O),
      'X' => %w(G S),
      nil => %w(B E I R T U)
    }.inject({}) do |map, (type, codes)|
      codes.each { |code| map[code] = type }
      map
    end

    # Map vendor's AVS result code to a street match code
    STREET_MATCH_CODE = {
      'Y' => %w(A B D H J M O Q T V X Y),
      'N' => %w(C K L N W Z),
      'X' => %w(G S),
      nil => %w(E F I P R U)
    }.inject({}) do |map, (type, codes)|
      codes.each { |code| map[code] = type }
      map
    end

    attr_reader :code, :message, :street_match, :postal_match

    def self.messages
      MESSAGES
    end

    def initialize(attrs)
      attrs ||= {}

      @code = attrs[:code].upcase unless attrs[:code].blank?
      @message = self.class.messages[code]

      if attrs[:street_match].blank?
        @street_match = STREET_MATCH_CODE[code]
      else
        @street_match = attrs[:street_match].upcase
      end

      if attrs[:postal_match].blank?
        @postal_match = POSTAL_MATCH_CODE[code]
      else
        @postal_match = attrs[:postal_match].upcase
      end
    end

    def to_hash
      { 'code' => code,
        'message' => message,
        'street_match' => street_match,
        'postal_match' => postal_match }
    end
  end
end