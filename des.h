#ifndef DES_HEADER
#define DES_HEADER

#include <stdint.h>

void permutate(const uint8_t* input_array,
                   const unsigned int input_bit_count,
                   uint8_t* output_array,
                   const unsigned int output_bit_cunt,
                   const unsigned int* permutation_array);
__device__
void permutate_gpu(const uint8_t* input_array,
                   const unsigned int input_bit_count,
                   uint8_t* output_array,
                   const unsigned int output_bit_cunt,
                   const unsigned int* permutation_array);

__device__
uint64_t initial_permutation(const uint64_t* message);
__device__
uint64_t inverse_initial_permutation(const uint64_t* data);

//even though the key permutations are not 64 bits, it's worth wasting some bits to let the stack handle memory
uint64_t key_permutation_first(const uint64_t* key);
uint64_t key_permutation_second(const uint64_t* key);

__device__
uint64_t expansion_permutation(const uint32_t* r);
__device__
uint32_t p_permutation(const uint32_t* data);

// rotates 28 bit values
// should at most rotate 4, which is fine because max(KEY_SHIFT_ARRAY) == 2
uint32_t left_shift_rotate(const uint32_t data, const unsigned int shifts);

uint64_t* generate_subkeys(const uint64_t key);
uint64_t* reverse_order(const uint64_t* keys);

uint64_t concatCD(const uint32_t c, const uint32_t d);

__device__
uint32_t feistal(const uint32_t* r, const uint64_t* key);

__device__
uint32_t s_box_transformation(const uint64_t* data);
__device__
uint8_t s_value(const uint8_t b, const unsigned int* s_box);

__device__
uint32_t calculate_r(const uint32_t prev_l, const uint32_t prev_r, const uint64_t* key);

__global__
void des(const uint64_t* message, const uint64_t* subkeys, uint64_t* output_block);

uint64_t* encode(const uint64_t* message, const unsigned int size, const uint64_t key);
uint64_t* decode(const uint64_t* encoded, const unsigned int size, const uint64_t key);

uint64_t pkcs5_padding(const uint64_t* block, unsigned int amount_of_bytes_to_pad);
//returns the amount of bytes removed
//updates the block to prepare for writing
unsigned int count_padding_bytes(const uint64_t* blocks, const unsigned int byte_count);

void print_help_message();

void write_to_file(const char* file_name, const uint8_t* data, const unsigned int file_size);

#endif
