#! /usr/bin/env python3

import csv
import math
from itertools import permutations
import random
import subprocess
import string
import time


# file sizes in bytes
def test(constants_file_name, thread_counts, file_sizes):
    files_to_encrypt = []
    for file_size in file_sizes:
        input_file_name = 'file_to_encrypt'
        file_name = input_file_name + str(file_size)
        files_to_encrypt.append(file_name)

        generate_input_file(file_name, file_size)

    with open('cuda_log.csv', 'w') as cuda_log:
        fieldnames = ['thread_count', 'cuda_block_count', 'file_size (Bytes)', 'Execution time (ms)']
        log = csv.DictWriter(cuda_log, fieldnames=fieldnames)

        original_content = read_file(constants_file_name)
        for thread_count in thread_counts:
            update_constants_file(constants_file_name, original_content, thread_count)
            compile()

            for idx, file_size in enumerate(file_sizes):
                log_execution(log, thread_count, cuda_block_count(file_size, thread_count), file_size, execution_main_test(files_to_encrypt[idx], './des'))

    subprocess.call(['rm'] + files_to_encrypt)

def cuda_block_count(file_size, thread_count):
    # one thread per block
    # One block is 8 bytes
    return math.ceil(file_size / (thread_count * 8))

def clean_up(input_file_name, files_to_encrypt, decrypted_file_name):
    subprocess.call(['rm', input_file_name, encrypted_file_name, decrypted_file_name])

def log_execution(log, thread_count, cuda_block_count, file_size, execution_time):
    log.writerow({'thread_count': thread_count, 
                    'cuda_block_count': cuda_block_count,
                    'file_size (Bytes)': file_size, 
                    'Execution time (ms)':execution_time})
def compile():
    subprocess.call(['make'])

# return execution time
def execution_main_test(input_file_name, executable_file_name):
    key = randomize_key()
    encrypted_file_name = 'encrypted'

    start_time = time.time()
    subprocess.call([executable_file_name, '-e', input_file_name, '-k', key, encrypted_file_name])
    execution_time = time.time() - start_time

    decrypted_file_name = 'decrypted'
    subprocess.call([executable_file_name, '-d', encrypted_file_name, '-k', key, decrypted_file_name])

    # throw if the input file and the decrypted file are not equal
    ret_val = subprocess.call(['cmp', input_file_name, decrypted_file_name])
    if ret_val != 0:
        raise ValueError('Did not decrypt properly')

    subprocess.call(['rm', encrypted_file_name, decrypted_file_name])

    return execution_time

def randomize_key():
    key = ''
    for i in range(8):
        key += random.choice(string.ascii_letters)
    return key

def generate_input_file(output_file_name, file_size):
    bs = 'bs=1'
    if file_size > 10**3:
        bs = 'bs=1000'
        file_size //= 10**3
    elif file_size > 10**6:
        bs = 'bs=1000000'
        file_size //= 10**6

    subprocess.call(['dd', 'if=/dev/urandom', 'of=' + output_file_name, bs, 'count=' + str(file_size)])

def read_file(filename):
    with open(filename, 'r') as f:
        return f.read()
    return None

def update_constants_file(constants_file_name, content, thread_count):
    with open(constants_file_name, 'w') as fd:
        for line in content.splitlines():
            if 'CUDA_THREAD_COUNT_PER_BLOCK' in line:
                fd.write(cuda_thread_count_string(thread_count))
            else:
                fd.write(line)
            fd.write('\n')

def cuda_thread_count_string(thread_count):
    return 'const unsigned int CUDA_THREAD_COUNT_PER_BLOCK = ' + str(thread_count) + ';'

if __name__ == '__main__':
    contants_file_name = 'constants.h'
    thread_counts = [32, 64, 128, 256, 512, 1024]
    # 1B 8B 1kB 5kB 1M 500M 1G
    # not using 64bit aligned to make it a bit harder for the algorithm
    file_sizes = [1, 8, 10**3, 5*10**3, 10**6, 5*10**8, 10**9]

    test(contants_file_name, thread_counts, file_sizes)
