# distutils: language=c++

from libc.stdint cimport int64_t
from hummingbot.strategy.strategy_base cimport StrategyBase
from hummingbot.connector.exchange_base cimport ExchangeBase
from hummingbot.core.data_type.limit_order cimport LimitOrder

from .order_id_market_pair_tracker import OrderIDMarketPairTracker

cdef class CrossExchangeSpreaderStrategy(StrategyBase):
    cdef:
        set _maker_markets
        set _ref_markets
        bint _all_markets_ready
        object _order_amount
        double _order_spread
        double _status_report_interval
        int64_t _logging_options
        OrderIDMarketPairTracker _market_pair_tracker
        bint _hb_app_notification
        list _maker_order_ids

    cdef c_process_market_pair(self,
                               object market_pair,
                               list active_orders)

    cdef object c_get_order_size(self,
                                 object market_pair,
                                 bint is_bid)

    cdef tuple c_get_top_bid_ask(self, str trading_pair, ExchangeBase market)

    cdef object c_get_limit_order_size(self, object market_pair)

    cdef object c_get_order_limit_price(self,
                                        object market_pair,
                                        bint is_bid,
                                        object size)

    cdef c_check_if_order_needs_to_adjust(self, object market_pair, LimitOrder active_order)

    cdef c_place_new_orders(self,
                            object market_pair,
                            bint has_active_bid,
                            bint has_active_ask)

    cdef str c_place_order(self,
                           object market_pair,
                           bint is_buy,
                           object amount,
                           object price)
