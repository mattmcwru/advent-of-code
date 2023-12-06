#import <stdio.h>
#import <string.h>

#define LINE_LENGTH 20

int main() {

    FILE *fp = fopen("data.txt", "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    char input_str[LINE_LENGTH];

    do {
        if (NULL == fgets(input_str, sizeof(input_str), fp)) {
            break;
        }

        printf("%s", input_str);


    } while (!feof(fp));


    fclose(fp);

    return 0;
}
