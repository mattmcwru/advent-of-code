#import <stdio.h>

int main() {
    printf("---<<< Day 1 >>>---\n\n");

    FILE *f = fopen("data.txt", "r");
    if (f == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    char d;
    int floor = 0;
    int position = 0;
    int bentry = 0;

    do {
        d = fgetc(f);
        position++;

        switch(d) {
            case '(': floor++; break;
            case ')': floor--; break;

            case EOF: break;
            case '\n' : break;
            default:
                printf("Bad input %c\n", d);
        }

        if (bentry == 0 && floor == -1) {
            printf("Entered basement @ %d\n", position);
            bentry = position;
        }
    }
    while (d != EOF);

    printf("Final Floor: %d\n", floor);

    fclose(f);

    return 0;
}
