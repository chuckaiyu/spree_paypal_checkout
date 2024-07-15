module Spree
  class PaypalCheckoutController < StoreController
    skip_before_action :verify_authenticity_token

    def create
      order = current_order || raise(ActiveRecord::RecordNotFound)
      items = order.line_items.map(&method(:line_item))

      additional_adjustments = order.all_adjustments.additional
      tax_adjustments = additional_adjustments.tax
      shipping_adjustments = additional_adjustments.shipping
      promotion_adjustments = additional_adjustments.promotion

      additional_adjustments.eligible.each do |adjustment|
        next if adjustment.amount.zero?
        next if tax_adjustments.include?(adjustment) || shipping_adjustments.include?(adjustment) || promotion_adjustments.include?(adjustment)

        items << {
          name: adjustment.label,
          quantity: 1,
          unit_amount: {
            currency_code: order.currency,
            value: adjustment.amount
          }
        }
      end

      response = provider.create_order(request_body(order: order, items: items, tax_adjustments: tax_adjustments, promotion_adjustments: promotion_adjustments))

      render json: response
    end

    private

    def line_item(item)
      {
        name: item.product.name,
        sku: item.variant.sku,
        quantity: item.quantity,
        description: item.product.meta_description,
        unit_amount: {
          currency_code: item.order.currency,
          value: item.price
        },
        category: "PHYSICAL_GOODS"
      }
    end

    def address_options
      address = current_order.ship_address

      {
        name: { full_name: address.try(:full_name) },
        address: {
          address_line_1: address.address1,
          address_line_2: address.address2,
          admin_area_1: address.state_text,
          admin_area_2: address.city,
          country_code: address.country.iso,
          postal_code: address.zipcode
        },
        type: 'SHIPPING'
      }
    end

    def payment_method
      @payment_method ||= Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def provider
      payment_method
    end

    def request_body(order: , items: , tax_adjustments: , promotion_adjustments: )
      {
        intent: payment_method.intent,
        purchase_units: [{
          reference_id: order.number,
          amount: {
            currency_code: current_order.currency,
            value: order.total,
            breakdown: {
              item_total: {
                currency_code: current_order.currency,
                value: items.sum { |r| (r[:unit_amount][:value] * r[:quantity]) }
              },
              shipping: {
                currency_code: current_order.currency,
                value: current_order.shipments.sum(:cost)
              },
              tax_total: {
                currency_code: current_order.currency,
                value: tax_adjustments.sum(:amount)
              },
              discount: {
                currency_code: current_order.currency,
                value: promotion_adjustments.sum(:amount).abs
              }
            }
          },
          items: items,
          shipping: address_options
        }]
      }
    end
  end
end