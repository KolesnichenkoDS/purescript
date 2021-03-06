{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveDataTypeable #-}

module Language.PureScript.Kinds where

import Prelude.Compat

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Data (Data)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson.BetterErrors (Parse, key, asText, asIntegral, nth, fromAesonParser, toAesonParser, throwCustomError)
import Data.Aeson ((.=))
import qualified Data.Aeson as A

import Language.PureScript.Names
import qualified Language.PureScript.Constants as C

-- | The data type of kinds
data Kind
  -- | Unification variable of type Kind
  = KUnknown Int
  -- | Kinds for labelled, unordered rows without duplicates
  | Row Kind
  -- | Function kinds
  | FunKind Kind Kind
  -- | A named kind
  | NamedKind (Qualified (ProperName 'KindName))
  deriving (Data, Show, Eq, Ord, Generic)

instance NFData Kind

-- This is equivalent to the derived Aeson ToJSON instance, except that we
-- write it out manually so that we can define a parser which is
-- backwards-compatible.
instance A.ToJSON Kind where
  toJSON kind = case kind of
    KUnknown i ->
      obj "KUnknown" i
    Row k ->
      obj "Row" k
    FunKind k1 k2 ->
      obj "FunKind" [k1, k2]
    NamedKind n ->
      obj "NamedKind" n
    where
    obj :: A.ToJSON a => Text -> a -> A.Value
    obj tag contents =
      A.object [ "tag" .= tag, "contents" .= contents ]

-- This is equivalent to the derived Aeson FromJSON instance, except that it
-- also handles JSON generated by compilers up to 0.10.3 and maps them to the
-- new representations (i.e. NamedKinds which are defined in the Prim module).
kindFromJSON :: Parse Text Kind
kindFromJSON = do
  t <- key "tag" asText
  case t of
    "KUnknown" ->
      KUnknown <$> key "contents" (nth 0 asIntegral)
    "Star" ->
      pure kindType
    "Row" ->
      Row <$> key "contents" kindFromJSON
    "FunKind" ->
      let
        kindAt n = key "contents" (nth n kindFromJSON)
      in
        FunKind <$> kindAt 0 <*> kindAt 1
    "Symbol" ->
      pure kindSymbol
    "NamedKind" ->
      NamedKind <$> key "contents" fromAesonParser
    other ->
      throwCustomError (T.append "Unrecognised tag: " other)

  where
  -- The following are copied from Environment and reimplemented to avoid
  -- circular dependencies.
  primName :: Text -> Qualified (ProperName a)
  primName = Qualified (Just $ ModuleName [ProperName C.prim]) . ProperName

  primKind :: Text -> Kind
  primKind = NamedKind . primName

  kindType = primKind "Type"
  kindSymbol = primKind "Symbol"

instance A.FromJSON Kind where
  parseJSON = toAesonParser id kindFromJSON

everywhereOnKinds :: (Kind -> Kind) -> Kind -> Kind
everywhereOnKinds f = go
  where
  go (Row k1) = f (Row (go k1))
  go (FunKind k1 k2) = f (FunKind (go k1) (go k2))
  go other = f other

everywhereOnKindsM :: Monad m => (Kind -> m Kind) -> Kind -> m Kind
everywhereOnKindsM f = go
  where
  go (Row k1) = (Row <$> go k1) >>= f
  go (FunKind k1 k2) = (FunKind <$> go k1 <*> go k2) >>= f
  go other = f other

everythingOnKinds :: (r -> r -> r) -> (Kind -> r) -> Kind -> r
everythingOnKinds (<>) f = go
  where
  go k@(Row k1) = f k <> go k1
  go k@(FunKind k1 k2) = f k <> go k1 <> go k2
  go other = f other
