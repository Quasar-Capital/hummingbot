from typing import List, Tuple

from hummingbot.client.config.global_config_map import global_config_map
from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.cross_exchange_spreader.cross_exchange_spreader_pairs import CrossExchangeSpreaderPairs
from hummingbot.strategy.cross_exchange_spreader.cross_exchange_spreader import CrossExchangeSpreaderStrategy
from hummingbot.strategy.cross_exchange_spreader.cross_exchange_spreader_config_map import \
    cross_exchange_spreader_config_map as config_map


def start(self):
    maker_market = config_map.get("maker_market").value.lower()
    ref_market = config_map.get("ref_market").value.lower()
    strategy_report_interval = global_config_map.get("strategy_report_interval").value
    raw_maker_trading_pair = config_map.get("maker_market_trading_pair")
    raw_ref_trading_pair = config_map.get("ref_market_trading_pair")
    order_amount = config_map.get("order_amount").value
    order_spread = config_map.get("order_spread").value

    try:
        maker_trading_pair: str = raw_maker_trading_pair
        ref_trading_pair: str = raw_ref_trading_pair
        maker_assets: Tuple[str, str] = self._initialize_market_assets(maker_market, [maker_trading_pair])[0]
    except ValueError as e:
        self._notify(str(e))
        return

    market_names: List[Tuple[str, List[str]]] = [
        (maker_market, [maker_trading_pair]),
        (ref_market, [ref_trading_pair]),
    ]

    self._initialize_wallet(token_trading_pairs=list(set(maker_assets)))
    self._initialize_markets(market_names)
    self.assets = set(maker_assets)

    maker_data = [self.markets[maker_market], maker_trading_pair] + list(maker_assets)
    ref_data = [self.market[ref_market], ref_trading_pair]

    maker_market_trading_pair_tuple = MarketTradingPairTuple(*maker_data)
    ref_market_trading_pair_tuple = MarketTradingPairTuple(*ref_data)

    self.market_trading_pair_tuples = [maker_market_trading_pair_tuple, ref_market_trading_pair_tuple]
    self.market_pairs = CrossExchangeSpreaderPairs(maker=maker_market_trading_pair_tuple,
                                                   ref=ref_market_trading_pair_tuple)

    strategy_logging_options = (
        CrossExchangeSpreaderStrategy.OPTION_LOG_CREATE_ORDER
        | CrossExchangeSpreaderStrategy.OPTION_LOG_ADJUST_ORDER
        | CrossExchangeSpreaderStrategy.OPTION_LOG_MAKER_ORDER_FILLED
        | CrossExchangeSpreaderStrategy.OPTION_LOG_REMOVING_ORDER
        | CrossExchangeSpreaderStrategy.OPTION_LOG_STATUS_REPORT
        | CrossExchangeSpreaderStrategy.OPTION_LOG_MAKER_ORDER_HEDGED
    )

    self.strategy = CrossExchangeSpreaderStrategy(
        market_pairs=[self.market_pairs],
        status_report_interval=strategy_report_interval,
        logging_options=strategy_logging_options,
        order_amount=order_amount,
        order_spread=order_spread,
        hb_app_notification=True,
    )
