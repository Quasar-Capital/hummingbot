import logging
from typing import (
    List,
    Tuple,
    Optional
)
from decimal import Decimal
from libc.stdint cimport int64_t

from hummingbot.strategy.strategy_base cimport StrategyBase

from .cross_exchange_spreader_pair import CrossExchangeSpreaderPair
from .order_id_market_pair_tracker import OrderIDMarketPairTracker

s_logger = None

cdef class CrossExchangeSpreaderStrategy(StrategyBase):
    OPTION_LOG_ALL = 0x7fffffffffffffff

    @classmethod
    def logger(cls):
        global s_logger

        if s_logger is None:
            s_logger = logging.getLogger(__name__)
        return s_logger

    def __init__(self,
                 market_pairs: List[CrossExchangeSpreaderPair],
                 order_amount: Optional[Decimal] = Decimal("0.0"),
                 logging_options: int = OPTION_LOG_ALL,
                 status_report_interval: float = 900,
                 hb_app_notification: bool = False
                 ):
        """
        Initializes a cross exchange spreader market making strategy object.

        :param market_pairs: list of cross exchange market pairs
        :param order_amount: override the limit order trade size, in base asset units
        :param logging_options: bit field for what types of logging to enable in this strategy object
        :param status_report_interval: what is the time interval between outputting new network warnings
        :param hb_app_notification: notify hummingbird app
        """

        if len(market_pairs) < 0:
            raise ValueError(f"market_pairs must not be empty.")

        super().__init__()

        self.market_pairs = {
            (market_pair.maker.market, market_pair.maker.trading_pair): market_pair for market_pair in market_pairs
        }
        self._maker_markets = set([market_pair.maker.market for market_pair in market_pairs])
        self._ref_markets = set([market_pair.ref.market for market_pair in market_pairs])
        self._hedger_markets = set([market_pair.hedger.market for market_pair in market_pairs])
        self._all_markets_ready = False
        self._logging_options = <int64_t>logging_options
        self._hb_app_notification = hb_app_notification
        self._maker_order_ids = []

        cdef:
            list all_markets = list(self._maker_markets | self._ref_markets | self._hedger_markets)

        self.c_add_markets(all_markets)

    def notify_hb_app(self, msg: str):
        if self._hb_app_notification:
            from hummingbot.client.hummingbot_application import HummingbotApplication
            HummingbotApplication.main_application()._notify(msg)
