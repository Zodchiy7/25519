//
//  Curve25519.m
//  BuildTests
//
//  Created by Frederic Jacobs on 22/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Curve25519.h"
#import "Randomness.h"
#import "ge.h"
#import "crypto_hash_sha512.h"
#import "crypto_sign.h"

NSString * const TSECKeyPairPublicKey   = @"TSECKeyPairPublicKey";
NSString * const TSECKeyPairPrivateKey  = @"TSECKeyPairPrivateKey";
NSString * const TSECKeyPairPreKeyId    = @"TSECKeyPairPreKeyId";

extern void curve25519_donna(unsigned char *output, const unsigned char *a, const unsigned char *b);

extern int  curve25519_sign(unsigned char* signature_out, /* 64 bytes */
                     const unsigned char* curve25519_privkey, /* 32 bytes */
                     const unsigned char* msg, const unsigned long msg_len,
                     const unsigned char* random); /* 64 bytes */

@implementation ECKeyPair

+ (BOOL)supportsSecureCoding{
    return YES;
}

-(void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBytes:self->publicKey length:ECCKeyLength forKey:TSECKeyPairPublicKey];
    [coder encodeBytes:self->privateKey length:ECCKeyLength forKey:TSECKeyPairPrivateKey];
}

-(id)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        NSUInteger returnedLength = 0;
        const uint8_t *returnedBuffer = NULL;
        // De-serialize public key
        returnedBuffer = [coder decodeBytesForKey:TSECKeyPairPublicKey returnedLength:&returnedLength];
        if (returnedLength != ECCKeyLength) {
            return nil;
        }
        memcpy(self->publicKey, returnedBuffer, ECCKeyLength);
        
        // De-serialize private key
        returnedBuffer = [coder decodeBytesForKey:TSECKeyPairPrivateKey returnedLength:&returnedLength];
        if (returnedLength != ECCKeyLength) {
            return nil;
        }
        memcpy(self->privateKey, returnedBuffer, ECCKeyLength);
    }
    return self;
}


+(ECKeyPair*)generateKeyPair{
    ECKeyPair* keyPair =[[ECKeyPair alloc] init];
    
    // Generate key pair as described in https://code.google.com/p/curve25519-donna/
    memcpy(keyPair->privateKey, [[Randomness  generateRandomBytes:32] bytes], 32);
    keyPair->privateKey[0]  &= 248;
    keyPair->privateKey[31] &= 127;
    keyPair->privateKey[31] |= 64;
    
    static const uint8_t basepoint[ECCKeyLength] = {9};
    curve25519_donna(keyPair->publicKey, keyPair->privateKey, basepoint);

    return keyPair;
}

+(ECKeyPair*)generateKeyPairBySeed:(unsigned char*)seed {
    ECKeyPair* keyPair =[[ECKeyPair alloc] init];
    
    crypto_hash_sha512(keyPair->privateKey, seed, 32);
    keyPair->privateKey[0]  &= 248;
    keyPair->privateKey[31] &= 127;
    keyPair->privateKey[31] |= 64;
    
    static const uint8_t basepoint[ECCKeyLength] = {9};
    curve25519_donna(keyPair->publicKey, keyPair->privateKey, basepoint);
    
    ge_p3 A;
    ge_scalarmult_base(&A, keyPair->privateKey);
    ge_p3_tobytes(keyPair->publicKey, &A);
    
    return keyPair;
}

-(NSData*) publicKey {
    return [NSData dataWithBytes:self->publicKey length:32];
}

-(NSData*) sign:(NSData*)data{
    Byte signatureBuffer[ECCSignatureLength];
    NSData *randomBytes = [Randomness generateRandomBytes:64];
    
    if(curve25519_sign(signatureBuffer, self->privateKey, [data bytes], [data length], [randomBytes bytes]) == -1 ){
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Message couldn't be signed." userInfo:nil];
    }
    
    NSData *signature = [NSData dataWithBytes:signatureBuffer length:ECCSignatureLength];
    
    return signature;
}

-(NSData*) generateSharedSecretFromPublicKey:(NSData*)theirPublicKey {
    unsigned char *sharedSecret = NULL;
    
    if ([theirPublicKey length] != 32) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"The supplied public key does not contain 32 bytes" userInfo:nil];
    }
    
    sharedSecret = malloc(32);
    
    if (sharedSecret == NULL) {
        free(sharedSecret);
        return nil;
    }
    
    curve25519_donna(sharedSecret,self->privateKey, [theirPublicKey bytes]);
    
    NSData *sharedSecretData = [NSData dataWithBytes:sharedSecret length:32];
    
    free(sharedSecret);
    
    return sharedSecretData;
}

@end

@implementation Curve25519

+(ECKeyPair*)generateKeyPair{
    return [ECKeyPair generateKeyPair];
}

+(ECKeyPair*)generateKeyPairBySeed:(unsigned char*)seed {
    return [ECKeyPair generateKeyPairBySeed:seed];
}

+(NSData*)generateSharedSecretFromPublicKey:(NSData *)theirPublicKey andKeyPair:(ECKeyPair *)keyPair{
    return [keyPair generateSharedSecretFromPublicKey:theirPublicKey];
}


+ (NSData*)signatures:(NSData*)secretKey message:(NSData*)message {
    
    NSMutableData *outData = [NSMutableData dataWithLength:crypto_sign_BYTES];
    unsigned char *sig = [outData mutableBytes];
    const unsigned char *m = [message bytes];
    unsigned long long mlen = [message length];
    const unsigned char *sk = [secretKey bytes];
    unsigned long long smlen_p;
    crypto_sign(sig, &smlen_p, m, mlen, sk);
    
    NSLog(@"%d %@", (int)outData.length, outData.description);
    
    return outData;
}

+ (NSData*)cryptoHashSha512:(NSData*)publicKey {
    NSMutableData *outData = [NSMutableData dataWithLength:64];
    unsigned char *hash = [outData mutableBytes];
    crypto_hash_sha512(hash, [publicKey bytes], 32);
    return outData;
}

+ (void)cryptoHashSha512:(unsigned char*)hash publicKey:(unsigned char*)publicKey {
    crypto_hash_sha512(hash, publicKey, 32);
}

@end
