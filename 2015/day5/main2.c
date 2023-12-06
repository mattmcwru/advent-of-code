#import <stdio.h>
#import <string.h>

int main() {
    char buf[20];
    int are_nice = 0;

    FILE *fp = fopen("data.txt", "r");    

    while ((NULL != fgets(buf, sizeof(buf), fp))) {
        char has_pair = 0;
        char has_repeat = 0;

        for (int i = 0; i < strlen(buf)-1 && !has_pair; i++) {
            for (int j = i+2; j < strlen(buf)-1; j++) {
                if (buf[i] == buf[j] && buf[i+1] == buf[j+1]) {
                    has_pair++;
                    break;
                }
            }
        }

        for (int i = 0; i < strlen(buf)-2; i++) {
            if (buf[i] == buf[i+2]) {
                has_repeat++;
                break;
            }
        }

        if (has_pair && has_repeat)
            are_nice++;
    }

    printf("%d nice\n", are_nice);

    fclose(fp);
    return 0;
}