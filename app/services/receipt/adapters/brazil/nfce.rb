# app/services/receipt/adapters/brazil/nfce.rb
module Receipt
  module Adapters
    module Brazil
      class Nfce < Base
        def call(url)
          xml_raw = fetch(url)
          doc     = parse(xml_raw)

          Normalized.new(
            receipt_id: doc.at_xpath('//chNFe')&.text,
            receipt_url: doc.at_xpath('//qrCode')&.text || url,
            raw: xml_raw,
            items: parse_items(doc),
            vendor: parse_vendor(doc),
            amount_cents: (total(doc) * 100).round,
            currency: 'BRL',
            occurred_at: doc.at_xpath('//dhEmi')&.text
          )
        end

        private

        # SEFAZ portals redirect http -> https (often onto a non-standard
        # port like :444); Net::HTTP.get does not follow redirects, so
        # we have to do it explicitly.
        def fetch(url, redirects_remaining = 5)
          raise 'Too many redirects' if redirects_remaining <= 0

          uri = URI.parse(url)
          raise ArgumentError, 'Not an HTTP(S) URL' unless uri.is_a?(URI::HTTP)

          response = Net::HTTP.get_response(uri)

          if response.is_a?(Net::HTTPRedirection)
            fetch(response['location'], redirects_remaining - 1)
          else
            response.body
          end
        end

        # SEFAZ-PE (and likely other states) appends stray trailing
        # garbage (a duplicate <protNFe>, a literal "null") after
        # </nfeProc>; RECOVER tolerates it instead of raising.
        def parse(xml_raw)
          doc = Nokogiri::XML(xml_raw, nil, nil, Nokogiri::XML::ParseOptions::RECOVER)
          doc.remove_namespaces!
          doc
        end

        def total(doc)
          doc.at_xpath('//total/ICMSTot/vNF')&.text.to_f
        end

        def parse_items(doc)
          doc.xpath('//det/prod').map do |prod|
            {
              'name' => prod.at_xpath('xProd')&.text,
              'quantity' => prod.at_xpath('qCom')&.text.to_f,
              'unit_price' => prod.at_xpath('vUnCom')&.text.to_f,
              'total' => prod.at_xpath('vProd')&.text.to_f
            }
          end
        end

        def parse_vendor(doc)
          emit  = doc.at_xpath('//emit')
          ender = emit&.at_xpath('enderEmit')

          {
            'name' => emit&.at_xpath('xNome')&.text,
            'fantasy_name' => emit&.at_xpath('xFant')&.text,
            'cnpj' => emit&.at_xpath('CNPJ')&.text,
            'address' => [ender&.at_xpath('xLgr')&.text, ender&.at_xpath('nro')&.text].compact.join(', '),
            'city' => ender&.at_xpath('xMun')&.text,
            'state' => ender&.at_xpath('UF')&.text,
            'payment_method' => doc.at_xpath('//pag/detPag/tPag')&.text
          }
        end
      end
    end
  end
end
