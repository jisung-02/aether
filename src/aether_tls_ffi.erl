%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%% Aether TLS Crypto FFI Module
%% ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
%%
%% Thin shim over the OTP `crypto` and `public_key` applications for the
%% TLS 1.3 handshake primitives that Gleam cannot reach directly: x25519
%% key exchange, certificate-key signing/verification, and PEM decoding.
%% All protocol logic (key schedule, message framing, state machine)
%% lives in Gleam; this module only adapts return values to
%% Gleam-friendly shapes and holds the opaque `public_key` key records.
%%

-module(aether_tls_ffi).

-include_lib("public_key/include/public_key.hrl").

-export([
    x25519_generate/0,
    x25519_public/1,
    x25519_shared/2,
    key_scheme/1,
    sign/2,
    verify_with_certificate/4,
    decode_pem_certificates/1,
    decode_pem_private_key/1,
    rsa_key_from_components/8,
    read_file/1
]).

%% PSS padding options shared by RSA sign and verify (rsa_pss_rsae_sha256,
%% RFC 8446 Section 4.2.3: salt length equals the digest length).
-define(RSA_PSS_OPTS, [
    {rsa_padding, rsa_pkcs1_pss_padding},
    {rsa_pss_saltlen, -1},
    {rsa_mgf1_md, sha256}
]).

%% @doc Generates an x25519 key pair. Returns {PublicKey, PrivateKey}.
-spec x25519_generate() -> {binary(), binary()}.
x25519_generate() ->
    crypto:generate_key(ecdh, x25519).

%% @doc Derives the public key for an existing x25519 private key.
-spec x25519_public(binary()) -> binary().
x25519_public(Private) ->
    {Public, _} = crypto:generate_key(ecdh, x25519, Private),
    Public.

%% @doc Computes the x25519 shared secret. Returns {error, nil} if the
%% peer public key is invalid (crypto raises on badarg).
-spec x25519_shared(binary(), binary()) -> {ok, binary()} | {error, nil}.
x25519_shared(PeerPublic, Private) ->
    try crypto:compute_key(ecdh, PeerPublic, Private, x25519) of
        Shared -> {ok, Shared}
    catch
        _:_ -> {error, nil}
    end.

%% @doc Returns the signature scheme atom matching the key's type, by
%% record tag: ecdsa_secp256r1_sha256 for #'ECPrivateKey'{}, or
%% rsa_pss_rsae_sha256 for #'RSAPrivateKey'{}.
-spec key_scheme(#'ECPrivateKey'{} | #'RSAPrivateKey'{}) -> atom().
key_scheme(Key) when element(1, Key) =:= 'ECPrivateKey' ->
    ecdsa_secp256r1_sha256;
key_scheme(Key) when element(1, Key) =:= 'RSAPrivateKey' ->
    rsa_pss_rsae_sha256.

%% @doc Signs `Message` with `Key`. ECDSA keys produce a DER-encoded
%% signature over sha256 (matches TLS scheme 0x0403). RSA keys produce an
%% RSASSA-PSS signature with sha256/MGF1-sha256 and salt length equal to
%% the digest length (matches TLS scheme 0x0804).
-spec sign(#'ECPrivateKey'{} | #'RSAPrivateKey'{}, binary()) -> binary().
sign(#'ECPrivateKey'{} = Key, Message) ->
    public_key:sign(Message, sha256, Key);
sign(#'RSAPrivateKey'{} = Key, Message) ->
    public_key:sign(Message, sha256, Key, ?RSA_PSS_OPTS).

%% @doc Verifies `Signature` over `Message` against the public key
%% embedded in the DER-encoded certificate `CertDer`, under `Scheme`
%% (an atom: ecdsa_secp256r1_sha256 | rsa_pss_rsae_sha256). Any decode
%% failure, algorithm mismatch, or verification failure returns false.
-spec verify_with_certificate(binary(), atom(), binary(), binary()) -> boolean().
verify_with_certificate(CertDer, Scheme, Message, Signature) ->
    try
        Cert = public_key:pkix_decode_cert(CertDer, otp),
        #'OTPCertificate'{tbsCertificate = Tbs} = Cert,
        #'OTPTBSCertificate'{subjectPublicKeyInfo = Spki} = Tbs,
        #'OTPSubjectPublicKeyInfo'{
            algorithm = #'PublicKeyAlgorithm'{parameters = Params},
            subjectPublicKey = Key
        } = Spki,
        do_verify(Scheme, Key, Params, Message, Signature)
    catch
        _:_ -> false
    end.

do_verify(rsa_pss_rsae_sha256, #'RSAPublicKey'{} = Key, _Params, Message, Signature) ->
    public_key:verify(Message, sha256, Signature, Key, ?RSA_PSS_OPTS);
do_verify(ecdsa_secp256r1_sha256, #'ECPoint'{} = Key, Params, Message, Signature) ->
    public_key:verify(Message, sha256, Signature, {Key, Params});
do_verify(_, _, _, _, _) ->
    false.

%% @doc Decodes every certificate entry from a PEM file, in file order,
%% as raw DER bytes. {error, nil} if the PEM contains no certificates.
-spec decode_pem_certificates(binary()) -> {ok, [binary()]} | {error, nil}.
decode_pem_certificates(Pem) ->
    try
        Entries = public_key:pem_decode(Pem),
        Ders = [Der || {'Certificate', Der, not_encrypted} <- Entries],
        case Ders of
            [] -> {error, nil};
            _ -> {ok, Ders}
        end
    catch
        _:_ -> {error, nil}
    end.

%% @doc Decodes the first unencrypted private key entry (PKCS#8
%% PrivateKeyInfo, or legacy EC/RSA PEM) from a PEM file.
-spec decode_pem_private_key(binary()) ->
    {ok, #'ECPrivateKey'{} | #'RSAPrivateKey'{}} | {error, nil}.
decode_pem_private_key(Pem) ->
    try
        Entries = public_key:pem_decode(Pem),
        case find_private_key_entry(Entries) of
            {ok, Entry} ->
                case public_key:pem_entry_decode(Entry) of
                    #'ECPrivateKey'{} = Key -> {ok, Key};
                    #'RSAPrivateKey'{} = Key -> {ok, Key};
                    _ -> {error, nil}
                end;
            error ->
                {error, nil}
        end
    catch
        _:_ -> {error, nil}
    end.

find_private_key_entry([]) ->
    error;
find_private_key_entry([{Type, _, _} = Entry | _]) when
    Type =:= 'PrivateKeyInfo';
    Type =:= 'ECPrivateKey';
    Type =:= 'RSAPrivateKey'
->
    {ok, Entry};
find_private_key_entry([_ | Rest]) ->
    find_private_key_entry(Rest).

%% @doc Builds an RSA private key record from its raw components
%% (test support: constructs the RFC 8448 server key from the RFC's
%% published RSA parameters). All arguments are big-endian binaries.
-spec rsa_key_from_components(
    binary(), binary(), binary(), binary(), binary(), binary(), binary(), binary()
) -> #'RSAPrivateKey'{}.
rsa_key_from_components(N, E, D, P, Q, E1, E2, C) ->
    #'RSAPrivateKey'{
        version = 'two-prime',
        modulus = binary:decode_unsigned(N),
        publicExponent = binary:decode_unsigned(E),
        privateExponent = binary:decode_unsigned(D),
        prime1 = binary:decode_unsigned(P),
        prime2 = binary:decode_unsigned(Q),
        exponent1 = binary:decode_unsigned(E1),
        exponent2 = binary:decode_unsigned(E2),
        coefficient = binary:decode_unsigned(C),
        otherPrimeInfos = asn1_NOVALUE
    }.

%% @doc Reads a file's raw bytes. Test support only, so the state machine
%% and Gleam production code never need direct filesystem access.
-spec read_file(binary() | string()) -> {ok, binary()} | {error, nil}.
read_file(Path) ->
    case file:read_file(Path) of
        {ok, Data} -> {ok, Data};
        {error, _} -> {error, nil}
    end.
