#import <stdio.h>
#import <stdint.h>
#import <string.h>

typedef union {
    char c[2];
    uint16_t ui;
} last_t; 

const last_t ab = {.c = "ab"};
const last_t cd = {.c = "cd"};
const last_t pq = {.c = "pq"};
const last_t xy = {.c = "xy"};


int main() {
    char buf[20];
    int are_nice = 0;

    last_t last = {0};

    FILE *fp = fopen("data.txt", "r");    

    while ((NULL != fgets(buf, sizeof(buf), fp))) {
        char has_double = 0;
        char has_vowels = 0;
        char is_bad = 0;

        for (int i = 0; i < strlen(buf); i++) {

            last.c[0] = last.c[1];
            last.c[1] = buf[i];
            
            //printf("%c  %c%c  %04x\n", buf[i], last.c[1], last.c[0], last.ui);

            switch(buf[i]) {
                case 'a':
                case 'e':
                case 'i':
                case 'o':
                case 'u': has_vowels++; break;
            }

            if (last.ui == ab.ui ||
                last.ui == cd.ui ||
                last.ui == pq.ui ||
                last.ui == xy.ui) {
                //printf("%c%c == %c%c\n", last.c[1], last.c[0], ab.c[1], ab.c[0]);
                is_bad++;
            }

            if (last.c[0] == last.c[1]) {
                has_double++;
            }
        }

        if (!is_bad && has_vowels >= 3 && has_double > 0)
            are_nice++;
    }

    printf("%d nice\n", are_nice);

    fclose(fp);
    return 0;
}