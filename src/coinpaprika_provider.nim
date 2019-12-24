import json
import httpclient
import ./workers_channels
import ./coin_cfg

const gCoinpaprikaEndpoint = "https://api.coinpaprika.com/v1/";

const fiats : array[2, string] = ["usd-us-dollars", "eur-euro"]

proc processInternal(coin: CoinConfigParams, fiat: string) : CoinpaprikaPrice =
    let url = gCoinpaprikaEndpoint & "price-converter?base_currency_id=" & coin["coinpaprika_id"].getStr() & "&quote_currency_id=" & fiat & "&amount=1"
    echo url
    var client = newHttpClient()
    var price: string
    try:
        var data = parseJson(client.getContent(url))
        echo "resp: ", data
        price = $data["price"]
    except HttpRequestError as e:
        echo "Got exception HttpRequestError: ", e.msg
    result = (coin["coin"].getStr, price)


proc processPaprikaProvider*(coin: CoinConfigParams) : bool =
    {.gcsafe.}:
        echo "refreshing provider"
        if coin["coinpaprika_id"].getStr() == "test-coin":
          result = true
          return
        var tunnel: array[2, CoinpaprikaPrice] = [processInternal(coin, fiats[0]), processInternal(coin, fiats[1])]  
        if tunnel[0].price.len > 0:
            discard paprikaChannel.trySend(tunnel)