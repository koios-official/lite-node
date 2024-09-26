CREATE OR REPLACE FUNCTION {{SCHEMA}}.policy_asset_addresses(_asset_policy text)
RETURNS TABLE (
  asset_name text,
  payment_address varchar,
  stake_address varchar,
  quantity text
)
LANGUAGE sql STABLE
AS $$
BEGIN
  SELECT
    ENCODE(ma.name, 'hex') AS asset_name,
    txo.address::varchar,
    sa.view::varchar as stake_address,
    SUM(mto.quantity)::text
  FROM multi_asset AS ma
  LEFT JOIN ma_tx_out AS mto ON mto.ident = ma.id
  LEFT JOIN tx_out AS txo ON txo.id = mto.tx_out_id
  LEFT JOIN stake_address as sa on txo.stake_address_id = sa.id
  WHERE ma.policy = DECODE(_asset_policy, 'hex')
    AND txo.consumed_by_tx_id IS NULL
  GROUP BY
    ma.name,
    txo.address,
    sa.view;
END;
$$;

COMMENT ON FUNCTION {{SCHEMA}}.policy_asset_addresses IS 'Returns a list of addresses with quantity for each asset ON a given policy'; -- noqa: LT01
