{-# LANGUAGE CPP, ForeignFunctionInterface, EmptyDataDecls #-}
-- |
-- Module      : Database.RocksDB.C
-- Copyright   : (c) 2012-2013 The rocksdb-haskell Authors
-- License     : BSD3
-- Maintainer  : kim.altintop@gmail.com
-- Stability   : experimental
-- Portability : non-portable
--

module Database.RocksDB.C where

import Foreign
import Foreign.C.Types
import Foreign.C.String

#ifdef mingw32_HOST_OS
#include <rocksdb\c.h>
#else
#include <rocksdb/c.h>
#endif

data RocksDB
data LCache
data LComparator
data LIterator
data LLogger
data LOptions
data LReadOptions
data LSnapshot
data LWriteBatch
data LWriteOptions
data PrefixExtractor
data Checkpoint

type RocksDBPtr      = Ptr RocksDB
type CachePtr        = Ptr LCache
type ComparatorPtr   = Ptr LComparator
type IteratorPtr     = Ptr LIterator
type LoggerPtr       = Ptr LLogger
type OptionsPtr      = Ptr LOptions
type ReadOptionsPtr  = Ptr LReadOptions
type SnapshotPtr     = Ptr LSnapshot
type WriteBatchPtr   = Ptr LWriteBatch
type WriteOptionsPtr = Ptr LWriteOptions

type DBName = CString
type ErrPtr = Ptr CString
type Key    = CString
type Val    = CString

newtype CompressionOpt = CompressionOpt { compressionOpt :: CInt }
  deriving (Eq, Show)
#{enum CompressionOpt, CompressionOpt
 , noCompression     = 0
 , snappyCompression = 1
 , zlibCompression   = 2
 , bz2Compression    = 3
 , lz4Compression    = 4
 , lz4hcCompression  = 5
 }


foreign import ccall safe "rocksdb\\c.h rocksdb_open"
  c_rocksdb_open :: OptionsPtr -> DBName -> ErrPtr -> IO RocksDBPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_open_for_read_only"
  c_rocksdb_open_for_read_only :: OptionsPtr -> DBName -> CChar -> ErrPtr -> IO RocksDBPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_open_with_ttl"
  c_rocksdb_open_with_ttl :: OptionsPtr -> DBName -> CInt -> ErrPtr -> IO RocksDBPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_close"
  c_rocksdb_close :: RocksDBPtr -> IO ()


foreign import ccall safe "rocksdb\\c.h rocksdb_put"
  c_rocksdb_put :: RocksDBPtr
                -> WriteOptionsPtr
                -> Key -> CSize
                -> Val -> CSize
                -> ErrPtr
                -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_delete"
  c_rocksdb_delete :: RocksDBPtr
                   -> WriteOptionsPtr
                   -> Key -> CSize
                   -> ErrPtr
                   -> IO ()


foreign import ccall unsafe "cpp\\chainweb-rocksdb.h rocksdb_delete_range"
    rocksdb_delete_range
        :: RocksDBPtr
        -> WriteOptionsPtr
        -> CString {- min key -}
        -> CSize {- min key length -}
        -> CString {- max key length -}
        -> CSize {- max key length -}
        -> Ptr CString {- output: errptr -}
        -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_write"
  c_rocksdb_write :: RocksDBPtr
                  -> WriteOptionsPtr
                  -> WriteBatchPtr
                  -> ErrPtr
                  -> IO ()

-- | Returns NULL if not found. A malloc()ed array otherwise. Stores the length
-- of the array in *vallen.
foreign import ccall safe "rocksdb\\c.h rocksdb_get"
  c_rocksdb_get :: RocksDBPtr
                -> ReadOptionsPtr
                -> Key -> CSize
                -> Ptr CSize        -- ^ value length
                -> ErrPtr
                -> IO CString

-- // if values_list[i] == NULL and errs[i] == NULL,
-- // then we got status.IsNotFound(), which we will not return.
-- // all errors except status status.ok() and status.IsNotFound() are returned.
-- //
-- // errs, values_list and values_list_sizes must be num_keys in length,
-- // allocated by the caller.
-- // errs is a list of strings as opposed to the conventional one error,
-- // where errs[i] is the status for retrieval of keys_list[i].
-- // each non-NULL errs entry is a malloc()ed, null terminated string.
-- // each non-NULL values_list entry is a malloc()ed array, with
-- // the length for each stored in values_list_sizes[i].
-- extern ROCKSDB_LIBRARY_API void rocksdb_multi_get(
--     rocksdb_t* db, const rocksdb_readoptions_t* options, size_t num_keys,
--     const char* const* keys_list, const size_t* keys_list_sizes,
--     char** values_list, size_t* values_list_sizes, char** errs);
--
foreign import ccall unsafe "rocksdb\\c.h rocksdb_multi_get"
    rocksdb_multi_get
        :: RocksDBPtr
        -> ReadOptionsPtr
        -> CSize
            -- ^ num_key
        -> Ptr (Ptr CChar)
            -- ^ keys_list
        -> Ptr CSize
            -- ^ keys_list_sizes
        -> Ptr (Ptr CChar)
            -- ^ values_list
        -> Ptr CSize
            -- ^ values_list_sizes
        -> Ptr CString
            -- ^ errs
        -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_create_snapshot"
  c_rocksdb_create_snapshot :: RocksDBPtr -> IO SnapshotPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_release_snapshot"
  c_rocksdb_release_snapshot :: RocksDBPtr -> SnapshotPtr -> IO ()

-- | Returns NULL if property name is unknown. Else returns a pointer to a
-- malloc()-ed null-terminated value.
foreign import ccall safe "rocksdb\\c.h rocksdb_property_value"
  c_rocksdb_property_value :: RocksDBPtr -> CString -> IO CString

foreign import ccall safe "rocksdb\\c.h rocksdb_approximate_sizes"
  c_rocksdb_approximate_sizes :: RocksDBPtr
                              -> CInt                     -- ^ num ranges
                              -> Ptr CString -> Ptr CSize -- ^ range start keys (array)
                              -> Ptr CString -> Ptr CSize -- ^ range limit keys (array)
                              -> Ptr Word64               -- ^ array of approx. sizes of ranges
                              -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_destroy_db"
  c_rocksdb_destroy_db :: OptionsPtr -> DBName -> ErrPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_repair_db"
  c_rocksdb_repair_db :: OptionsPtr -> DBName -> ErrPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_compact_range"
    rocksdb_compact_range
        :: RocksDBPtr
        -> CString {- min key -}
        -> CSize {- min key length -}
        -> CString {- max key -}
        -> CSize {- max key length -}
        -> IO ()

--
-- Iterator
--

foreign import ccall safe "rocksdb\\c.h rocksdb_create_iterator"
  c_rocksdb_create_iterator :: RocksDBPtr -> ReadOptionsPtr -> IO IteratorPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_destroy"
  c_rocksdb_iter_destroy :: IteratorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_valid"
  c_rocksdb_iter_valid :: IteratorPtr -> IO CUChar

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_seek_to_first"
  c_rocksdb_iter_seek_to_first :: IteratorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_seek_to_last"
  c_rocksdb_iter_seek_to_last :: IteratorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_seek"
  c_rocksdb_iter_seek :: IteratorPtr -> Key -> CSize -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_next"
  c_rocksdb_iter_next :: IteratorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_prev"
  c_rocksdb_iter_prev :: IteratorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_key"
  c_rocksdb_iter_key :: IteratorPtr -> Ptr CSize -> IO Key

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_value"
  c_rocksdb_iter_value :: IteratorPtr -> Ptr CSize -> IO Val

foreign import ccall safe "rocksdb\\c.h rocksdb_iter_get_error"
  c_rocksdb_iter_get_error :: IteratorPtr -> ErrPtr -> IO ()


--
-- Write batch
--

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_create"
  c_rocksdb_writebatch_create :: IO WriteBatchPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_destroy"
  c_rocksdb_writebatch_destroy :: WriteBatchPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_clear"
  c_rocksdb_writebatch_clear :: WriteBatchPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_put"
  c_rocksdb_writebatch_put :: WriteBatchPtr
                           -> Key -> CSize
                           -> Val -> CSize
                           -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_delete"
  c_rocksdb_writebatch_delete :: WriteBatchPtr -> Key -> CSize -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_writebatch_iterate"
  c_rocksdb_writebatch_iterate :: WriteBatchPtr
                               -> Ptr ()                            -- ^ state
                               -> FunPtr (Ptr () -> Key -> CSize -> Val -> CSize) -- ^ put
                               -> FunPtr (Ptr () -> Key -> CSize)     -- ^ delete
                               -> IO ()


--
-- Options
--

foreign import ccall safe "rocksdb\\c.h rocksdb_options_create"
  c_rocksdb_options_create :: IO OptionsPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_options_destroy"
  c_rocksdb_options_destroy :: OptionsPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_comparator"
  c_rocksdb_options_set_comparator :: OptionsPtr -> ComparatorPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_create_if_missing"
  c_rocksdb_options_set_create_if_missing :: OptionsPtr -> CUChar -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_error_if_exists"
  c_rocksdb_options_set_error_if_exists :: OptionsPtr -> CUChar -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_paranoid_checks"
  c_rocksdb_options_set_paranoid_checks :: OptionsPtr -> CUChar -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_info_log"
  c_rocksdb_options_set_info_log :: OptionsPtr -> LoggerPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_write_buffer_size"
  c_rocksdb_options_set_write_buffer_size :: OptionsPtr -> CSize -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_max_open_files"
  c_rocksdb_options_set_max_open_files :: OptionsPtr -> CInt -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_options_set_compression"
  c_rocksdb_options_set_compression :: OptionsPtr -> CompressionOpt -> IO ()

--
-- Comparator
--

type StatePtr   = Ptr ()
type Destructor = StatePtr -> ()
type CompareFun = StatePtr -> CString -> CSize -> CString -> CSize -> IO CInt
type NameFun    = StatePtr -> CString

-- | Make a FunPtr to a user-defined comparator function
foreign import ccall "wrapper" mkCmp :: CompareFun -> IO (FunPtr CompareFun)

-- | Make a destructor FunPtr
foreign import ccall "wrapper" mkDest :: Destructor -> IO (FunPtr Destructor)

-- | Make a name FunPtr
foreign import ccall "wrapper" mkName :: NameFun -> IO (FunPtr NameFun)

foreign import ccall safe "rocksdb\\c.h rocksdb_comparator_create"
  c_rocksdb_comparator_create :: StatePtr
                              -> FunPtr Destructor
                              -> FunPtr CompareFun
                              -> FunPtr NameFun
                              -> IO ComparatorPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_comparator_destroy"
  c_rocksdb_comparator_destroy :: ComparatorPtr -> IO ()


--
-- Filter Policy
--

type CreateFilterFun = StatePtr
                     -> Ptr CString -- ^ key array
                     -> Ptr CSize   -- ^ key length array
                     -> CInt        -- ^ num keys
                     -> Ptr CSize   -- ^ filter length
                     -> IO CString  -- ^ the filter
type KeyMayMatchFun  = StatePtr
                     -> CString     -- ^ key
                     -> CSize       -- ^ key length
                     -> CString     -- ^ filter
                     -> CSize       -- ^ filter length
                     -> IO CUChar   -- ^ whether key is in filter

-- | Make a FunPtr to a user-defined create_filter function
foreign import ccall "wrapper" mkCF :: CreateFilterFun -> IO (FunPtr CreateFilterFun)

-- | Make a FunPtr to a user-defined key_may_match function
foreign import ccall "wrapper" mkKMM :: KeyMayMatchFun -> IO (FunPtr KeyMayMatchFun)

--
-- Read options
--

foreign import ccall safe "rocksdb\\c.h rocksdb_readoptions_create"
  c_rocksdb_readoptions_create :: IO ReadOptionsPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_readoptions_destroy"
  c_rocksdb_readoptions_destroy :: ReadOptionsPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_readoptions_set_verify_checksums"
  c_rocksdb_readoptions_set_verify_checksums :: ReadOptionsPtr -> CUChar -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_readoptions_set_fill_cache"
  c_rocksdb_readoptions_set_fill_cache :: ReadOptionsPtr -> CUChar -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_readoptions_set_snapshot"
  c_rocksdb_readoptions_set_snapshot :: ReadOptionsPtr -> SnapshotPtr -> IO ()

foreign import ccall unsafe "rocksdb\\c.h rocksdb_readoptions_set_iterate_upper_bound"
    rocksdb_readoptions_set_iterate_upper_bound :: ReadOptionsPtr -> CString -> CSize -> IO ()

foreign import ccall unsafe "rocksdb\\c.h rocksdb_readoptions_set_iterate_lower_bound"
    rocksdb_readoptions_set_iterate_lower_bound :: ReadOptionsPtr -> CString -> CSize -> IO ()

--
-- Write options
--

foreign import ccall safe "rocksdb\\c.h rocksdb_writeoptions_create"
  c_rocksdb_writeoptions_create :: IO WriteOptionsPtr

foreign import ccall safe "rocksdb\\c.h rocksdb_writeoptions_destroy"
  c_rocksdb_writeoptions_destroy :: WriteOptionsPtr -> IO ()

foreign import ccall safe "rocksdb\\c.h rocksdb_writeoptions_set_sync"
  c_rocksdb_writeoptions_set_sync :: WriteOptionsPtr -> CUChar -> IO ()


--
-- Cache
--

foreign import ccall safe "rocksdb\\c.h rocksdb_cache_create_lru"
  c_rocksdb_cache_create_lru :: CSize -> IO CachePtr

foreign import ccall safe "rocksdb\\c.h rocksdb_cache_destroy"
  c_rocksdb_cache_destroy :: CachePtr -> IO ()

----------------------------------------------------------------------------
-- Free
----------------------------------------------------------------------------

foreign import ccall safe "rocksdb\\c.h rocksdb_free"
  c_rocksdb_free :: CString -> IO ()

----------------------------------------------------------------------------
-- Checkpoints
----------------------------------------------------------------------------

foreign import ccall unsafe "rocksdb\\c.h rocksdb_checkpoint_object_create"
    rocksdb_checkpoint_object_create :: RocksDBPtr -> Ptr CString -> IO (Ptr Checkpoint)

foreign import ccall unsafe "rocksdb\\c.h rocksdb_checkpoint_create"
    rocksdb_checkpoint_create :: Ptr Checkpoint -> CString -> CULong -> Ptr CString -> IO ()

foreign import ccall unsafe "rocksdb\\c.h rocksdb_checkpoint_object_destroy"
    rocksdb_checkpoint_object_destroy :: Ptr Checkpoint -> IO ()
