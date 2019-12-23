import algorithm
import json
import options
import hashes
import sequtils
import locks
import tables
import sharedtables

import jsonschema

import ./utils
import ./cpp_bindings/folly/hashmap
import ./cpp_bindings/std/pair

##! Schema definitions
jsonSchema:
  ElectrumServerParams:
    url: string
    protocol ?: string
    disable_cert_verification ?: bool
  CoinConfigParams:
    coin: string
    asset ?: string
    name: string
    "type": string
    rpcport: int
    pubtype ?: int
    p2shtype ?: int
    wiftype ?: int
    txversion ?: int
    overwintered ?: int
    txfee ?: int
    mm2: int
    coingecko_id: string
    coinpaprika_id: string
    is_erc_20: bool
    electrum: ElectrumServerParams[]
    explorer_url: string[]
    active: bool
    currently_enabled: bool

export ElectrumServerParams
export CoinConfigParams
export `[]`
export `[]=`
export create
export unsafeAccess

var coinsRegistry: Table[string, CoinConfigParams]
var lock: Lock

##! Public functions
proc parseCfg*() =
    let entireFile = readFile(getAssetsPath() & "/config/coins.json")
    let jsonNode = parseJson(entireFile)
    for key in jsonNode.keys:
      if jsonNode[key].isValid(CoinConfigParams):
        var res = CoinConfigParams(jsonNode[key])
        lock.acquire()
        coinsRegistry[key] = res
        lock.release()
      else:
        echo jsonNode[key], " is invalid"
    echo "Coins config correctly launched: ", coinsRegistry.len()

proc getActiveCoins*() : seq[CoinConfigParams] =
  {.gcsafe.}:
    lock.acquire()
    for i, value in coinsRegistry:
        if value["active"].getBool:
            result.add(value)
    lock.release()

proc getEnabledCoins*() : seq[CoinConfigParams] =
  lock.acquire()
  for key, value in coinsRegistry:
      if value["currently_enabled"].getBool:
          result.add(value)
  lock.release()
  result.sort(proc (a, b: CoinConfigParams): int = cmp(a["coin"].getStr, b["coin"].getStr))

proc getEnableableCoins*() : seq[CoinConfigParams] =
  withLock(lock):
    for key, value in coinsRegistry:
        if not value["currently_enabled"].getBool:
            result.add(value)

proc getCoinInfo*(ticker: string): CoinConfigParams =   
  withLock(lock):
      result = coinsRegistry.getOrDefault(ticker)

proc updateCoinInfo*(ticker: string, current: CoinConfigParams, desired: CoinConfigParams) =
  withLock(lock):
    coinsRegistry[ticker] = desired

proc insertCoinInfo*(ticker: string, info: CoinConfigParams) =
  withLock(lock):
      coinsRegistry[ticker] = info

proc updateCoinInfoStatus*(coins: seq[CoinConfigParams]) =
  var node = parseFile(getAssetsPath() & "/config/coins.json")
  for i, coin in coins:
    node[coin["coin"].getStr()]["active"] = newJBool(true)
  writeFile(getAssetsPath() & "/config/coins.json", $node)
