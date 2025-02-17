{-# LANGUAGE CPP           #-}
{-# LANGUAGE TupleSections #-}

-- |
-- Module      : Database.RocksDB.Base
-- Copyright   : (c) 2012-2013 The leveldb-haskell Authors
--               (c) 2014 The rocksdb-haskell Authors
-- License     : BSD3
-- Maintainer  : mail@agrafix.net
-- Stability   : experimental
-- Portability : non-portable
--
-- RocksDB Haskell binding.
--
-- The API closely follows the C-API of RocksDB.
-- For more information, see: <http://agrafix.net>

module Database.RocksDB.Base
    ( -- * Exported Types
      DB
    , BatchOp (..)
    , Comparator (..)
    , Compression (..)
    , Options (..)
    , Snapshot
    , WriteBatch
    , WriteOptions (..)
    , Range

    -- * Defaults
    , defaultOptions
    , defaultWriteOptions

    -- * Basic Database Manipulations
    , open
    , openWithTTL
    , openReadOnly
    -- , openBracket
    , close
    , put
    , putBinaryVal
    , putBinary
    , delete
    , write
    , get
    , getBinary
    , getBinaryVal
    , withSnapshot
    -- , withSnapshotBracket
    , createSnapshot
    , releaseSnapshot

    -- * Administrative Functions
    , Property (..), getProperty
    , destroy
    , repair
    , approximateSize

    -- * Utility functions to help perform mass writes
    , binaryToBS
    , bsToBinary

    -- * Iteration
    , module Database.RocksDB.Iterator
    ) where

import           Control.Exception            (bracket, bracketOnError)
import           Control.Monad                (liftM, when)

import           Control.Monad.IO.Class       (MonadIO (liftIO))
import           Data.Binary                  (Binary)
import qualified Data.Binary                  as Binary
import           Data.ByteString              (ByteString)
import           Data.ByteString.Internal     (ByteString (..))
import qualified Data.ByteString.Lazy         as BSL
import           Foreign
import           Foreign.C.String             (CString, withCString)
import           System.Directory             (createDirectoryIfMissing)

import           Database.RocksDB.C
import           Database.RocksDB.Internal
import           Database.RocksDB.Iterator
import           Database.RocksDB.ReadOptions
import           Database.RocksDB.Types

import qualified Data.ByteString              as BS
import qualified Data.ByteString.Unsafe       as BU

import qualified GHC.Foreign                  as GHC
import qualified GHC.IO.Encoding              as GHC

openWith :: MonadIO m => (OptionsPtr -> CString -> ErrPtr -> IO RocksDBPtr) -> [Char] -> Options -> m DB
openWith opener path opts = liftIO $ bracketOnError initialize finalize mkDB
    where
# ifdef mingw32_HOST_OS
        initialize =
            (, ()) <$> mkOpts opts
        finalize (opts', ()) =
            freeOpts opts'
# else
        initialize = do
            opts' <- mkOpts opts
            -- With LC_ALL=C, two things happen:
            --   * rocksdb can't open a database with unicode in path;
            --   * rocksdb can't create a folder properly.
            -- So, we create the folder by ourselves, and for thart we
            -- need to set the encoding we're going to use. On Linux
            -- it's almost always UTC-8.
            oldenc <- GHC.getFileSystemEncoding
            when (createIfMissing opts) $
                GHC.setFileSystemEncoding GHC.utf8
            pure (opts', oldenc)
        finalize (opts', oldenc) = do
            freeOpts opts'
            GHC.setFileSystemEncoding oldenc
# endif
        mkDB (Options' opts_ptr _ _, _) = do
            when (createIfMissing opts) $
                createDirectoryIfMissing True path
            withFilePath path $ \path_ptr ->
                liftM DB
                $ throwIfErr "open"
                $ opener opts_ptr path_ptr

-- | Open a database.
--
-- The returned handle should be released with 'close'.
open :: MonadIO m => FilePath -> Options -> m DB
open = openWith c_rocksdb_open

-- | Open a database in read-only mode. Any changes made to the database after
-- the database is opened read-only will not be visible until re-opened.
--
-- The returned handle should be released with 'close'.
openReadOnly :: MonadIO m => FilePath -> Options -> m DB
openReadOnly = openWith (\o p -> c_rocksdb_open_for_read_only o p 0)

-- | Open a database with a TTL (in seconds) for keys.
--
-- The returned handle should be released with 'close'.
openWithTTL :: MonadIO m => FilePath -> Options -> Int -> m DB
openWithTTL path options ttl = 
    openWith (\o p -> c_rocksdb_open_with_ttl o p (fromIntegral ttl)) path options

-- | Close a database.
--
-- The handle will be invalid after calling this action and should no
-- longer be used.
close :: MonadIO m => DB -> m ()
close (DB db_ptr) = liftIO $
    c_rocksdb_close db_ptr

-- | Run an action with a 'Snapshot' of the database.
withSnapshot :: MonadIO m => DB -> (Snapshot -> IO a) -> m a
withSnapshot db act = liftIO $
    bracket (createSnapshot db) (releaseSnapshot db) act

-- | Create a snapshot of the database.
--
-- The returned 'Snapshot' should be released with 'releaseSnapshot'.
createSnapshot :: MonadIO m => DB -> m Snapshot
createSnapshot (DB db_ptr) = liftIO $
    Snapshot <$> c_rocksdb_create_snapshot db_ptr

-- | Release a snapshot.
--
-- The handle will be invalid after calling this action and should no
-- longer be used.
releaseSnapshot :: MonadIO m => DB -> Snapshot -> m ()
releaseSnapshot (DB db_ptr) (Snapshot snap) = liftIO $
    c_rocksdb_release_snapshot db_ptr snap

-- | Get a DB property.
getProperty :: MonadIO m => DB -> Property -> m (Maybe ByteString)
getProperty (DB db_ptr) p = liftIO $
    withCString (prop p) $ \prop_ptr -> do
        val_ptr <- c_rocksdb_property_value db_ptr prop_ptr
        if val_ptr == nullPtr
            then return Nothing
            else do res <- Just <$> BS.packCString val_ptr
                    freeCString val_ptr
                    return res
    where
        prop (NumFilesAtLevel i) = "rocksdb.num-files-at-level" ++ show i
        prop Stats               = "rocksdb.stats"
        prop SSTables            = "rocksdb.sstables"

-- | Destroy the given RocksDB database.
destroy :: MonadIO m => FilePath -> Options -> m ()
destroy path opts = liftIO $ bracket (mkOpts opts) freeOpts destroy'
    where
        destroy' (Options' opts_ptr _ _) =
            withFilePath path $ \path_ptr ->
                throwIfErr "destroy" $ c_rocksdb_destroy_db opts_ptr path_ptr

-- | Repair the given RocksDB database.
repair :: MonadIO m => FilePath -> Options -> m ()
repair path opts = liftIO $ bracket (mkOpts opts) freeOpts repair'
    where
        repair' (Options' opts_ptr _ _) =
            withFilePath path $ \path_ptr ->
                throwIfErr "repair" $ c_rocksdb_repair_db opts_ptr path_ptr

-- TODO: support [Range], like C API does
type Range  = (ByteString, ByteString)

-- | Inspect the approximate sizes of the different levels.
approximateSize :: MonadIO m => DB -> Range -> m Int64
approximateSize (DB db_ptr) (from, to) = liftIO $
    BU.unsafeUseAsCStringLen from $ \(from_ptr, flen) ->
    BU.unsafeUseAsCStringLen to   $ \(to_ptr, tlen)   ->
    withArray [from_ptr]          $ \from_ptrs        ->
    withArray [intToCSize flen]   $ \flen_ptrs        ->
    withArray [to_ptr]            $ \to_ptrs          ->
    withArray [intToCSize tlen]   $ \tlen_ptrs        ->
    allocaArray 1                 $ \size_ptrs        -> do
        c_rocksdb_approximate_sizes db_ptr 1
                                    from_ptrs flen_ptrs
                                    to_ptrs tlen_ptrs
                                    size_ptrs
        liftM head $ peekArray 1 size_ptrs >>= mapM toInt64

    where
        toInt64 = return . fromIntegral

putBinaryVal :: (MonadIO m, Binary v) => DB -> WriteOptions -> ByteString -> v -> m ()
putBinaryVal db wopts key val = put db wopts key (binaryToBS val)

putBinary :: (MonadIO m, Binary k, Binary v) => DB -> WriteOptions -> k -> v -> m ()
putBinary db wopts key val = put db wopts (binaryToBS key) (binaryToBS val)

-- | Write a key/value pair.
put :: MonadIO m => DB -> WriteOptions -> ByteString -> ByteString -> m ()
put (DB db_ptr) opts key value = liftIO $ withCWriteOpts opts $ \opts_ptr ->
    BU.unsafeUseAsCStringLen key   $ \(key_ptr, klen) ->
    BU.unsafeUseAsCStringLen value $ \(val_ptr, vlen) ->
        throwIfErr "put"
            $ c_rocksdb_put db_ptr opts_ptr
                            key_ptr (intToCSize klen)
                            val_ptr (intToCSize vlen)

getBinaryVal :: (Binary v, MonadIO m) => DB -> ReadOptions -> ByteString -> m (Maybe v)
getBinaryVal db ropts key  = fmap bsToBinary <$> get db ropts key

getBinary :: (MonadIO m, Binary k, Binary v) => DB -> ReadOptions -> k -> m (Maybe v)
getBinary db ropts key = fmap bsToBinary <$> get db ropts (binaryToBS key)

-- | Read a value by key.
get :: MonadIO m => DB -> ReadOptions -> ByteString -> m (Maybe ByteString)
get (DB db_ptr) opts key = liftIO $ withReadOptions opts $ \opts_ptr ->
    BU.unsafeUseAsCStringLen key $ \(key_ptr, klen) ->
    alloca                       $ \vlen_ptr -> do
        val_ptr <- throwIfErr "get" $
            c_rocksdb_get db_ptr opts_ptr key_ptr (intToCSize klen) vlen_ptr
        vlen <- peek vlen_ptr
        if val_ptr == nullPtr
            then return Nothing
            else do
                res' <- Just <$> BS.packCStringLen (val_ptr, cSizeToInt vlen)
                freeCString val_ptr
                return res'

-- | Delete a key/value pair.
delete :: MonadIO m => DB -> WriteOptions -> ByteString -> m ()
delete (DB db_ptr) opts key = liftIO $ withCWriteOpts opts $ \opts_ptr ->
    BU.unsafeUseAsCStringLen key $ \(key_ptr, klen) ->
        throwIfErr "delete"
            $ c_rocksdb_delete db_ptr opts_ptr key_ptr (intToCSize klen)

-- | Perform a batch mutation.
write :: MonadIO m => DB -> WriteOptions -> WriteBatch -> m ()
write (DB db_ptr) opts batch = liftIO $ withCWriteOpts opts $ \opts_ptr ->
    bracket c_rocksdb_writebatch_create c_rocksdb_writebatch_destroy $ \batch_ptr -> do

    mapM_ (batchAdd batch_ptr) batch

    throwIfErr "write" $ c_rocksdb_write db_ptr opts_ptr batch_ptr

    -- ensure @ByteString@s (and respective shared @CStringLen@s) aren't GC'ed
    -- until here
    mapM_ (liftIO . touch) batch

    where
        batchAdd batch_ptr (Put key val) =
            BU.unsafeUseAsCStringLen key $ \(key_ptr, klen) ->
            BU.unsafeUseAsCStringLen val $ \(val_ptr, vlen) ->
                c_rocksdb_writebatch_put batch_ptr
                                         key_ptr (intToCSize klen)
                                         val_ptr (intToCSize vlen)

        batchAdd batch_ptr (Del key) =
            BU.unsafeUseAsCStringLen key $ \(key_ptr, klen) ->
                c_rocksdb_writebatch_delete batch_ptr key_ptr (intToCSize klen)

        touch (Put (PS p _ _) (PS p' _ _)) = do
            touchForeignPtr p
            touchForeignPtr p'

        touch (Del (PS p _ _)) = touchForeignPtr p

binaryToBS :: Binary v => v -> ByteString
binaryToBS x = BSL.toStrict (Binary.encode x)

bsToBinary :: Binary v => ByteString -> v
bsToBinary x = Binary.decode (BSL.fromStrict x)

-- | Marshal a 'FilePath' (Haskell string) into a `NUL` terminated C string using
-- temporary storage.
-- On Linux, UTF-8 is almost always the encoding used.
-- When on Windows, UTF-8 can also be used, although the default for those devices is
-- UTF-16. For a more detailed explanation, please refer to
-- https://msdn.microsoft.com/en-us/library/windows/desktop/dd374081(v=vs.85).aspx.
withFilePath :: FilePath -> (CString -> IO a) -> IO a
withFilePath = GHC.withCString GHC.utf8
