%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Aether QUIC Crypto FFI Module
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%%
%% Thin shim over the OTP crypto application for the QUIC packet
%% protection primitives (RFC 9001 Section 5): AEAD seal/open and the
%% 5-byte header protection mask. All protocol logic lives in Gleam;
%% this module only adapts return values to Gleam-friendly shapes.
%%
%% The first argument of each function is the Gleam `Aead` constructor,
%% which compiles to the atoms aes128_gcm | aes256_gcm |
%% chacha20_poly1305.
%%

-module(aether_quic_crypto_ffi).

-export([aead_encrypt/5, aead_decrypt/6, hp_mask/3]).

cipher(aes128_gcm) -> aes_128_gcm;
cipher(aes256_gcm) -> aes_256_gcm;
cipher(chacha20_poly1305) -> chacha20_poly1305.

%% @doc Seals `Plain` and returns {CipherText, Tag}.
-spec aead_encrypt(atom(), binary(), binary(), binary(), binary()) ->
    {binary(), binary()}.
aead_encrypt(Aead, Key, Nonce, Aad, Plain) ->
    crypto:crypto_one_time_aead(cipher(Aead), Key, Nonce, Plain, Aad, true).

%% @doc Opens `CipherText`, verifying `Tag`. Returns {ok, Plain} or
%% {error, nil} on authentication failure.
-spec aead_decrypt(atom(), binary(), binary(), binary(), binary(), binary()) ->
    {ok, binary()} | {error, nil}.
aead_decrypt(Aead, Key, Nonce, Aad, CipherText, Tag) ->
    case crypto:crypto_one_time_aead(
        cipher(Aead), Key, Nonce, CipherText, Aad, Tag, false
    ) of
        error -> {error, nil};
        Plain -> {ok, Plain}
    end.

%% @doc Computes the 5-byte header protection mask from a 16-byte
%% ciphertext sample (RFC 9001 Section 5.4). AES ciphers encrypt the
%% sample with AES-ECB; ChaCha20 uses the sample as counter and nonce
%% (the raw ChaCha20 16-byte IV has the same layout) to encrypt five
%% zero bytes.
-spec hp_mask(atom(), binary(), binary()) -> binary().
hp_mask(aes128_gcm, HpKey, Sample) ->
    ecb_mask(aes_128_ecb, HpKey, Sample);
hp_mask(aes256_gcm, HpKey, Sample) ->
    ecb_mask(aes_256_ecb, HpKey, Sample);
hp_mask(chacha20_poly1305, HpKey, Sample) ->
    crypto:crypto_one_time(chacha20, HpKey, Sample, <<0, 0, 0, 0, 0>>, true).

ecb_mask(Cipher, Key, Sample) ->
    <<Mask:5/binary, _/binary>> = crypto:crypto_one_time(Cipher, Key, Sample, true),
    Mask.
