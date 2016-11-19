#include "stdlib.h"
#include "stdio.h"
#include "string.h"

#include "des.h"
#include "constants.h"

void permutate(const uint8_t* input_array,
    const unsigned int input_bit_count,
    uint8_t* output_array,
    const unsigned int output_bit_cunt,
    const unsigned int* permutation_array) {

  for(unsigned int i = 0; i < output_bit_cunt; ++i) {
    // all indexes in the permutation arrays are starting at 1
    unsigned int original_pos = permutation_array[i] - 1;

    // starts counting from left to right (MSB = 0)
    uint8_t original_index = (input_bit_count - original_pos - 1) / 8;
    uint8_t original_bit_pos = (input_bit_count - original_pos + 7) % 8;

    // use a bit mask to only have it be one bit, in the LSB
    uint8_t original_value = (input_array[original_index] & ( 1 << original_bit_pos )) >> original_bit_pos;

    uint8_t new_index = (output_bit_cunt - i - 1) / 8;
    uint8_t new_bit_pos = (output_bit_cunt - i + 7) % 8;
    output_array[new_index] |= original_value << new_bit_pos;
  }
}

__device__
void permutate_gpu(const uint8_t* input_array,
    const unsigned int input_bit_count,
    uint8_t* output_array,
    const unsigned int output_bit_cunt,
    const unsigned int* permutation_array) {
  for(unsigned int i = 0; i < output_bit_cunt; ++i) {
    // all indexes in the permutation arrays are starting at 1
    unsigned int original_pos = permutation_array[i] - 1;

    // starts counting from left to right (MSB = 0)
    uint8_t original_index = (input_bit_count - original_pos - 1) / 8;
    uint8_t original_bit_pos = (input_bit_count - original_pos + 7) % 8;

    // use a bit mask to only have it be one bit, in the LSB
    uint8_t original_value = (input_array[original_index] & ( 1 << original_bit_pos )) >> original_bit_pos;

    uint8_t new_index = (output_bit_cunt - i - 1) / 8;
    uint8_t new_bit_pos = (output_bit_cunt - i + 7) % 8;
    output_array[new_index] |= original_value << new_bit_pos;
  }
}

__device__
uint64_t initial_permutation(const uint64_t* message) {
  uint64_t permutated = 0;
  permutate_gpu((uint8_t*)message, BLOCK_SIZE, (uint8_t*)&permutated, BLOCK_SIZE, IP_PERMUTATION_ARRAY);
  return permutated;
}

__device__
uint64_t inverse_initial_permutation(const uint64_t* data) {
  uint64_t permutated = 0;
  permutate_gpu((uint8_t*)data, BLOCK_SIZE, (uint8_t*)&permutated, BLOCK_SIZE, INVERSE_IP_PERMUTATION_ARRAY);
  return permutated;
}

uint64_t key_permutation_first(const uint64_t* key) {
  uint64_t permutated = 0;
  permutate((uint8_t*)key, BLOCK_SIZE, (uint8_t*)&permutated, KEY_SIZE_FIRST_PERMUTATION, PC_1);
  return permutated;
}

uint64_t key_permutation_second(const uint64_t* key) {
  uint64_t permutated = 0;
  permutate((uint8_t*)key, KEY_SIZE_FIRST_PERMUTATION, (uint8_t*)&permutated, KEY_SIZE_SECOND_PERMUTATION, PC_2);
  return permutated;
}

__device__
uint64_t expansion_permutation(const uint32_t* r) {
  uint64_t permutated = 0;
  permutate_gpu((uint8_t*)r, BLOCK_SIZE / 2, (uint8_t*)&permutated, KEY_SIZE_SECOND_PERMUTATION, E);
  return permutated;
}

__device__
uint32_t p_permutation(const uint32_t* data) {
  uint32_t permutated = 0;
  permutate_gpu((uint8_t*)data, BLOCK_SIZE / 2, (uint8_t*)&permutated, BLOCK_SIZE / 2, P);
  return permutated;
}

uint32_t left_shift_rotate(const uint32_t data, const unsigned int shifts) {
  uint32_t x = data << shifts;

  // rotate the bits that got overflowed from the 28 LSB
  x |= x >> 28;
  // only use the 28 LSB
  x &= 0x0FFFFFFF;

  return x;
}

uint64_t* generate_subkeys(const uint64_t key) {
  // 56 bits
  uint64_t permutated_key = key_permutation_first(&key);

  const uint32_t c0 = permutated_key >> KEY_SIZE_FIRST_PERMUTATION / 2;
  const uint32_t d0 = (permutated_key << KEY_SIZE_FIRST_PERMUTATION / 2) >> KEY_SIZE_FIRST_PERMUTATION / 2;

  uint32_t cs[AMOUNT_OF_KEYS];
  uint32_t ds[AMOUNT_OF_KEYS];

  cs[0] = left_shift_rotate(c0, KEY_SHIFT_ARRAY[0]);
  ds[0] = left_shift_rotate(d0, KEY_SHIFT_ARRAY[0]);

  for(unsigned int i = 1; i < AMOUNT_OF_KEYS; ++i) {
    cs[i] = left_shift_rotate(cs[i - 1], KEY_SHIFT_ARRAY[i]);
    ds[i] = left_shift_rotate(ds[i - 1], KEY_SHIFT_ARRAY[i]);
  }

  uint64_t* subkeys = (uint64_t*)malloc(AMOUNT_OF_KEYS * sizeof(uint64_t));
  for(unsigned int i = 0; i < AMOUNT_OF_KEYS; ++i) {
    uint64_t k_pre_permutation = concatCD(cs[i], ds[i]);
    uint64_t k = key_permutation_second(&k_pre_permutation);

    subkeys[i] = k;
  }

  return subkeys;
}

uint64_t* reverse_order(const uint64_t* subkeys) {
  uint64_t* reversed = (uint64_t*)malloc(AMOUNT_OF_KEYS * sizeof(uint64_t));

  for(unsigned int i = 0; i < AMOUNT_OF_KEYS; ++i) {
    reversed[ AMOUNT_OF_KEYS - i - 1 ] = subkeys[i];
  }

  return reversed;
}

// the permutated key is 56 bits, and we want the 28 MSB
uint32_t getC0(const uint64_t* permutated_key) {
  // 3x8 = 24
  // 4 bits are from the LSB
  // we now have the 24 LSB of the MSB of the permutated key
  unsigned int start_index = 3;
  uint32_t c0 = (permutated_key[start_index] & 0xF0) >> 4;

  for(unsigned int i = 1; i < KEY_SIZE_FIRST_PERMUTATION / 8 - start_index; ++i) {
    c0 |= permutated_key[i + start_index] << (4 + (8 * (i - 1)));
  }

  return c0;
}

uint32_t getD0(const uint8_t* permutated_key) {
  uint32_t d0 = *((uint32_t*) permutated_key) & 0x0FFFFFFF;

  return d0;
}

uint64_t concatCD(const uint32_t c, const uint32_t d) {
  uint64_t concat = c;
  concat <<= 28;
  concat |= d;

  return concat;
}

__device__
uint32_t feistal(const uint32_t* r, const uint64_t* key) {
  const uint64_t expanded = expansion_permutation(r);
  const uint64_t xored = expanded ^ (*key);

  uint32_t s_transformed = s_box_transformation(&xored);

  const uint32_t p_permutated = p_permutation(&s_transformed);

  return p_permutated;
}

//  S8 is LSB, S1 is MSB
// data is 48 bits
__device__
uint32_t s_box_transformation(const uint64_t* data) {

  uint32_t val = 0;
  // use 6 LSB
  val = s_value((*data << 42) >> 42, S8_BOX);
  // use 4 LSB from *data as MSB and 2 MSB from *data as LSB
  val |= s_value((*data << 36) >> 42, S7_BOX)  << 4;
  // use 2 LSB from *data as MSB and 4 MSB from *data as LSB
  val |= s_value((*data << 30) >> 42, S6_BOX) << 8;
  // use 6 MSB
  val |= s_value((*data << 24) >> 42, S5_BOX) << 12;

  // use 6 LSB
  val |= s_value((*data << 18) >> 42, S4_BOX) << 16;
  // use 4 LSB from *data as MSB and 2 MSB from *data as LSB
  val |= s_value((*data << 12) >> 42, S3_BOX) << 20;
  // use 2 LSB from *data as MSB and 4 MSB from *data as LSB
  val |= s_value((*data << 6) >> 42, S2_BOX) << 24;
  // use 6 MSB
  val |= s_value(*data >> 42, S1_BOX) << 28;

  return val;
}

__device__
uint8_t s_value(const uint8_t b, const unsigned int* s_box) {
  // first and last
  unsigned int i = ((b & 0x20) >> 4) | (b & 0x1);
  // middle 4
  unsigned int j = (b & 0x1E) >> 1;

  return s_box[i * 16 + j];
}

__device__
uint32_t calculate_r(const uint32_t prev_l, const uint32_t prev_r, const uint64_t* key) {
  return prev_l ^ feistal(&prev_r, key);
}

__global__
void des(const uint64_t* message, const uint64_t* subkeys, uint64_t* output_block) {
  const uint64_t permutated = initial_permutation(message);

  uint32_t l = permutated >> 32;

  // will only use the 32 LSB
  uint32_t r = (permutated << 32) >> 32;

  for(unsigned int i = 0; i < AMOUNT_OF_KEYS; ++i) {
    uint32_t prev_l = l;
    l = r;
    r = calculate_r(prev_l, r, &subkeys[i]);
  }

  uint64_t concat = r;
  concat <<= 32;
  concat |= l;

  *output_block = inverse_initial_permutation(&concat);
}

uint64_t* encode(const uint64_t* message, const unsigned int size, const uint64_t key) {

  uint64_t* message_gpu;
  cudaMalloc(&message_gpu, size);
  cudaMemcpy(message_gpu, message, size, cudaMemcpyHostToDevice);

  uint64_t* subkeys = generate_subkeys(key);
  uint64_t* subkeys_gpu;
  cudaMalloc(&subkeys_gpu, 16 * sizeof(uint64_t));
  cudaMemcpy(subkeys_gpu, subkeys, 16 * sizeof(uint64_t), cudaMemcpyHostToDevice);

  free(subkeys);


  uint64_t* encoded_message_gpu;
  cudaMalloc(&encoded_message_gpu, size);

  for(unsigned int i = 0; i < size / sizeof(uint64_t); ++i) {
    des<<< 1,1 >>>(&message_gpu[i], subkeys_gpu, &encoded_message_gpu[i]);
  }

  uint64_t* encoded_message = (uint64_t*) malloc(size);
  cudaMemcpy(encoded_message, encoded_message_gpu, size, cudaMemcpyDeviceToHost);

  cudaFree(subkeys_gpu);
  cudaFree(message_gpu);
  cudaFree(encoded_message_gpu);

  return encoded_message;
}

uint64_t* decode(const uint64_t* encoded, const unsigned int size, const uint64_t key) {
  uint64_t* subkeys = generate_subkeys(key);
  uint64_t* reversed_subkeys = reverse_order(subkeys);

  uint64_t* decoded_message;
  cudaMalloc(&decoded_message, size);

  for(unsigned int i = 0; i < size / sizeof(uint64_t); ++i) {
     des<<< 1,1 >>>(&encoded[i], reversed_subkeys, &decoded_message[i]);
  }

  free(subkeys);
  free(reversed_subkeys);
  return decoded_message;
}

uint64_t pkcs5_padding(const uint64_t* block, unsigned int amount_of_bytes_to_pad) {
  uint64_t padded = *block;
  padded <<= amount_of_bytes_to_pad * 8;
  for(unsigned int i = 0; i < amount_of_bytes_to_pad; ++i) {
    ((uint8_t*)&padded)[i] = amount_of_bytes_to_pad;
  }

  return padded;
}

unsigned int count_padding_bytes(const uint64_t* block) {
  const uint8_t* bytes = (const uint8_t*) block;
  const unsigned int amount_of_bytes = BLOCK_SIZE / 8;; 
  const uint8_t prev_value = bytes[0];
  for(unsigned int i = 1; i < amount_of_bytes; ++i) {
    //if they're no longer equal, it should be the end of the padding
    if(bytes[i] != prev_value) {
      //but if it's not equal to the amount of padding added, then was not actually padding
      if(prev_value == i) {
        return i;
      }

      //if they were not equal and it was not equal to i, it was not padding
      break;
    }
  }

  return 0;
}

void print_help_message() {
  printf("Usage:\n\
      des -e input -k key output\n\
      des -d input -k key output\n");
}

void print_key_error_msg() {
  printf("Key has to be 8 characters long\n");
}

void write_to_file(const char* file_name, const uint8_t* data, const unsigned int file_size) {
  FILE* output_file = fopen(file_name, "wb");
  if(output_file == NULL) {
    printf("Could not open output file named %s", file_name);
  }
  //the amount of elements read is also the amounts of elements to be written
  const size_t elements_written = fwrite(data, sizeof(uint8_t), file_size, output_file);
  if(elements_written != file_size) {
    printf("Could not write to output file");
  }
  fclose(output_file);
}

int main(int argc, char** argv) {

  if(argc != 6) {
    print_help_message();
    return 0;
  }
  const char* input_file_name = argv[2];
  const char* key_string = argv[4];
  if(strlen(key_string) != 8) {
    print_key_error_msg();
    return 1;
  }
  const uint64_t key = *(uint64_t*)key_string;
  const char* output_file_name = argv[5];
  FILE* input_file = fopen(input_file_name, "rb");

  // obtain file size:
  fseek(input_file , 0 , SEEK_END);
  // in bytes
  const uint64_t file_size = ftell(input_file);
  rewind(input_file);

  //ceil the amount of elements to be read
  const size_t elements_to_read = (file_size + sizeof(uint64_t) - 1) / sizeof(uint64_t);

  uint64_t* file_buffer = (uint64_t*)malloc(elements_to_read * sizeof(uint64_t));
  fread(file_buffer, sizeof(uint8_t), file_size, input_file);

  fclose(input_file);

  if(strcmp(argv[1], "-e") == 0) {
    // add padding to the last element (if needed)
    const unsigned int output_byte_count = elements_to_read * sizeof(uint64_t);
    file_buffer[elements_to_read - 1] = pkcs5_padding(&file_buffer[elements_to_read - 1], output_byte_count - file_size);

    uint64_t* encoded_file_buffer = encode(file_buffer, output_byte_count, key);

    write_to_file(output_file_name, (uint8_t*)encoded_file_buffer, output_byte_count);

    free(encoded_file_buffer);

  } else if(strcmp(argv[1], "-d") == 0) {
    uint64_t* decoded_file_buffer = decode(file_buffer, file_size, key);
    const size_t bytes_of_padding = count_padding_bytes(decoded_file_buffer);
    decoded_file_buffer[ file_size / sizeof(uint64_t) - 1 ] >>= bytes_of_padding * 8;

    const size_t output_byte_count = file_size - bytes_of_padding;

    write_to_file(output_file_name, (uint8_t*)decoded_file_buffer, output_byte_count);

    free(decoded_file_buffer);
  } else {
    print_help_message();
  }

  free(file_buffer);
  return 0;
}
