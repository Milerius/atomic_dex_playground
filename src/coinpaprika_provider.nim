import json
import httpclient
import options
import logging
import tables

import ./balance
import ./cpp_bindings/boost/multiprecision
import ./mm2_api
import ./workers_channels
import ./coin_cfg
import ./utils

const gCoinpaprikaEndpoint = "https://api.coinpaprika.com/v1/";

const fiats : array[2, string] = ["usd-us-dollars", "eur-euro"]

proc processInternal(coin: CoinConfigParams, fiat: string) : CoinpaprikaPrice =
    let url = gCoinpaprikaEndpoint & "price-converter?base_currency_id=" & coin["coinpaprika_id"].getStr() & "&quote_currency_id=" & fiat & "&amount=1"
    debug("req: ", url)
    var client = newHttpClient()
    var price: string
    try:
        var data = parseJson(client.getContent(url))
        debug("resp: ", data)
        price = $data["price"]
    except HttpRequestError as e:
        warn("Got exception HttpRequestError: ", e.msg)
    var convertedFiat = ""
    if fiat == "usd-us-dollars":
        convertedFiat = "USD"
    elif fiat == "eur-euro":
        convertedFiat = "EUR"
    result = (coin["coin"].getStr, price, convertedFiat)


proc processPaprikaProvider*(coin: CoinConfigParams) : bool =
    {.gcsafe.}:
        debug("refreshing provider")
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

proc getPriceInFiat*(price: string, balanceRegistry: Table[string, BalanceAnswerSuccess], ticker: string): string = 
    var total = getPriceInFiatF(price, balanceRegistry, ticker)
    result = convertIt(total)

proc getPriceInFiatFromTx*(priceRegistry: Table[string, string], coin: CoinConfigParams, tx: TransactionData) : string =
    if coin["coinpaprika_id"].getStr() == "test-coin" or not priceRegistry.contains(coin["coin"].getStr()):
        result = "0.00"
        return
    let 
        my_balance_change = tx["my_balance_change"].getStr()
        am_i_sender = my_balance_change[0] == '-'
        amount = am_i_sender ? my_balance_change[1 .. ^1] ! my_balance_change
    var amount_f = constructTFloat50(amount)
    var current_rate_f = constructTFloat50(priceRegistry[coin["coin"].getStr()])
    var final_price_f = amount_f * current_rate_f
    result = convertIt(final_price_f)
    if am_i_sender:
        result = "-" & result
 
proc getWholeBalanceFiat*(priceRegistry: Table[string, string], balanceRegistry: Table[string, BalanceAnswerSuccess]) : string =
    var final_price_f: TFloat50
    for ticker, price in priceRegistry:
        var price_f = getPriceInFiatF(price, balanceRegistry, ticker)
        final_price_f = final_price_f + price_f
    result = convertIt(final_price_f)