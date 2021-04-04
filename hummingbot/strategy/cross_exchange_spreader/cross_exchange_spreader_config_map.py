from decimal import Decimal
from typing import Optional

from hummingbot.client.config.config_var import ConfigVar
from hummingbot.client.config.config_validators import validate_exchange, validate_market_trading_pair
from hummingbot.client.settings import required_exchanges, EXAMPLE_PAIRS
from hummingbot.client.config.config_helpers import minimum_order_amount


def maker_trading_pair_prompt():
    maker_market = cross_exchange_spreader_config_map.get("maker_market").value
    example = EXAMPLE_PAIRS.get(maker_market)
    return "Enter the token trading pair you would like to trade on maker market: %s%s >>> " % (
        maker_market,
        f" (e.g. {example})" if example else "",
    )


def ref_trading_pair_prompt():
    ref_market = cross_exchange_spreader_config_map.get("ref_market").value
    example = EXAMPLE_PAIRS.get(ref_market)
    return "Enter the token trading pair you would like to user as reference market: %s%s >>> " % (
        ref_market,
        f" (e.g. {example})" if example else "",
    )


# strategy specific validators
def validate_maker_market_trading_pair(value: str) -> Optional[str]:
    maker_market = cross_exchange_spreader_config_map.get("maker_market").value
    return validate_market_trading_pair(maker_market, value)


def validate_ref_market_trading_pair(value: str) -> Optional[str]:
    ref_market = cross_exchange_spreader_config_map.get("ref_market").value
    return validate_market_trading_pair(ref_market, value)


def order_amount_prompt() -> str:
    maker_exchange = cross_exchange_spreader_config_map["maker_market"].value
    trading_pair = cross_exchange_spreader_config_map["maker_market_trading_pair"].value
    base_asset, quote_asset = trading_pair.split("-")
    min_amount = minimum_order_amount(maker_exchange, trading_pair)
    return f"What is the amount of {base_asset} per order? (minimum {min_amount}) >>> "


def validate_order_amount(value: str) -> Optional[str]:
    try:
        maker_exchange = cross_exchange_spreader_config_map.get("maker_market").value
        trading_pair = cross_exchange_spreader_config_map["maker_market_trading_pair"].value
        min_amount = minimum_order_amount(maker_exchange, trading_pair)
        if Decimal(value) < min_amount:
            return f"Order amount must be at least {min_amount}."
    except Exception:
        return "Invalid order amount."


def order_spread_prompt() -> str:
    return "What is the spread to apply for each order? >>> "


def validate_order_spread(value: str) -> Optional[str]:
    try:
        if Decimal(value) < 0:
            return f"Order spread ({value}) must be greater than zero."
        if Decimal(value) > 1:
            return f"Order spread ({value}) must not be greater than 1"
    except Exception:
        return "Invalid order spread."


def ref_market_on_validated(value: str):
    required_exchanges.append(value)


cross_exchange_spreader_config_map = {
    "strategy": ConfigVar(key="strategy",
                          prompt="",
                          default="cross_exchange_spreader"
                          ),
    "maker_market": ConfigVar(
        key="maker_market",
        prompt="Enter your maker spot connector >>> ",
        prompt_on_new=True,
        validator=validate_exchange,
        on_validated=lambda value: required_exchanges.append(value),
    ),
    "ref_market": ConfigVar(
        key="ref_market",
        prompt="Enter your reference spot connector >>> ",
        prompt_on_new=True,
        validator=validate_exchange,
        on_validated=ref_market_on_validated,
    ),
    "maker_market_trading_pair": ConfigVar(
        key="maker_market_trading_pair",
        prompt=maker_trading_pair_prompt,
        prompt_on_new=True,
        validator=validate_maker_market_trading_pair
    ),
    "ref_market_trading_pair": ConfigVar(
        key="tref_market_trading_pair",
        prompt=ref_trading_pair_prompt,
        prompt_on_new=True,
        validator=validate_ref_market_trading_pair
    ),
    "order_amount": ConfigVar(
        key="order_amount",
        prompt=order_amount_prompt,
        prompt_on_new=True,
        type_str="decimal",
        validator=validate_order_amount,
    ),
    "order_spread": ConfigVar(
        key="order_spread",
        prompt=order_spread_prompt,
        prompt_on_new=True,
        type_str="decimal",
        validator=validate_order_spread,
    ),
}
