#!/usr/bin/env python

from typing import NamedTuple

from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple


class CrossExchangeSpreaderPairs(NamedTuple):
    """
    Specifies reference pair for market making

    TODO: Add ability to specify spread when defining pairs

    e.g. If I want to market make on dydx AAVE-DAI,
         reference from FTX OTC AAVE-DAI and
         hedge on Binance ETHUSDT:

         CrossExchangeSpreaderPair(
             dydx, "AAVE-DAI", "AAVE", "DAI",
             ftx_otc, "AAVE-DAI", "AAVE", "DAI",
             binance, "ETHUSDT", "ETH", "USDT",
         )
    """
    maker: MarketTradingPairTuple
    ref: MarketTradingPairTuple
