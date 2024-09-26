CREATE OR REPLACE FUNCTION {{SCHEMA}}.asset_addresses(_asset_policy text, _asset_name text DEFAULT '')
RETURNS TABLE (
  payment_address varchar,
  stake_address varchar,
  quantity text
)
LANGUAGE plpgsql
AS $$
DECLARE
  _asset_policy_decoded bytea;
  _asset_name_decoded bytea;
  _asset_id int;
BEGIN
  SELECT DECODE(_asset_policy, 'hex') INTO _asset_policy_decoded;
  SELECT DECODE(CASE
    WHEN _asset_name IS NULL THEN ''
    ELSE _asset_name
    END, 'hex') INTO _asset_name_decoded;
  SELECT id INTO _asset_id
    FROM multi_asset AS ma
    WHERE ma.policy = _asset_policy_decoded
      AND ma.name = _asset_name_decoded;

  RETURN QUERY
    SELECT
      x.address::varchar,
      x.stake_address::varchar,
      SUM(x.quantity)::text
    FROM
      (
        SELECT
          txo.address,
          sa.view as stake_address,
          mto.quantity
        FROM ma_tx_out AS mto
        LEFT JOIN tx_out AS txo ON txo.id = mto.tx_out_id
        LEFT JOIN stake_address sa on txo.stake_address_id = sa.id
        WHERE mto.ident = _asset_id
          AND txo.consumed_by_tx_id IS NULL
      ) AS x
    GROUP BY x.address, x.stake_address;
END;
$$;

COMMENT ON FUNCTION {{SCHEMA}}.asset_addresses IS 'Returns a list of addresses with quantity holding the specified asset'; -- noqa: LT01
