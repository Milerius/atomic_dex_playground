import json
import httpclient
import logging
import tables

import ./balance
import ./cpp_bindings/boost/multiprecision
import ./mm2_api
import ./workers_channels
import ./coin_cfg

const gCoinpaprikaEndpoint = "https://api.coinpaprika.com/v1/";

const fiats : array[2, string] = ["usd-us-dollars", "eur-euro"]

proc processInternal(coin: CoinConfigParams, fiat: string) : CoinpaprikaPrice =
    let url = gCoinpaprikaEndpoint & "price-converter?base_currency_id=" & coin["coinpaprika_id"].getStr() & "&quote_currency_id=" & fiat & "&amount=1"
    when not defined(windows):
        info("req: ", url)
    else:
        echo "req: ", url
    var client = newHttpClient()
    var price: string
    try:
        var data = parseJson(client.getContent(url))
        when not defined(windows):
            info("resp: ", data)
        else:
            echo "resp: ", data
        price = $data["price"]
    except HttpRequestError as e:
        echo "Got exception HttpRequestError: ", e.msg
    var convertedFiat = ""
    if fiat == "usd-us-dollars":
        convertedFiat = "USD"
    elif fiat == "eur-euro":
        convertedFiat = "EUR"
    result = (coin["coin"].getStr, price, convertedFiat)


proc processPaprikaProvider*(coin: CoinConfigParams) : bool =
    {.gcsafe.}:
        when not defined(windows):
            info("refreshing provider")
        else:
            echo "refreshing provider"
        if coin["coinpaprika_id"].getStr() == "test-coin":
          result = true
          return
        var tunnel: array[2, CoinpaprikaPrice] = [processInternal(coin, fiats[0]), processInternal(coin, fiats[1])]  
        if tunnel[0].price.len > 0:
            discard paprikaChannel.trySend(tunnel)

proc getPriceInFiatF(price: string, balanceRegistry: Table[string, BalanceAnswerSuccess], ticker: string) : TFloat50 =
    if not balanceRegistry.contains(ticker):
        result = constructTFloat50("0.00")
        return
    var price_f = constructTFloat50(price)
    var amount = constructTFloat50(myBalance(balanceRegistry[ticker]))
    var total = price_f * amount
    result = total

proc convertIt(value: TFloat50, precision: int = 2) : string =
    var ss: StdStringStream
    ss.setPrecision(2)
    ss << value
    result = $ss.str()

proc getPriceInFiat(price: string, balanceRegistry: Table[string, BalanceAnswerSuccess], ticker: string): string = 
    var total = getPriceInFiatF(price, balanceRegistry, ticker)
    result = convertIt(total) 
 
proc getWholeBalanceFiat*(priceRegistry: Table[string, string], balanceRegistry: Table[string, BalanceAnswerSuccess]) : string =
    var final_price_f: TFloat50
    for ticker, price in priceRegistry:
        var price_f = getPriceInFiatF(price, balanceRegistry, ticker)
        final_price_f = final_price_f + price_f
    result = convertIt(final_price_f)