#import <stdio.h>

int main() {

    FILE *fp = fopen("data.txt", "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    char c;
    char parse_index = 0;
    int l = 0, w = 0, h = 0;
    int area = 0;
    int ribbon = 0;

    do {
        c = fgetc(fp);

        switch (c) {
            case '0' ... '9':
                switch (parse_index) {
                    case 0: l = (l * 10) + (c - '0'); break;
                    case 1: w = (w * 10) + (c - '0'); break;
                    case 2: h = (h * 10) + (c - '0'); break;
                }
                break;

            case 'x':
                parse_index++;
                break;

            case '\n':
                area += 2*l*w + 2*w*h + 2*h*l;
                area += l*w < w*h && l*w < h*l ? l*w : w*h < h*l ? w*h : h*l;

                ribbon += l > w && l > h ? 2*w+2*h : w > h ? 2*l+2*h : 2*l+2*w;
                ribbon += l*w*h;

                parse_index = l = w = h = 0;
                break;

            case EOF : break;

            default:
                printf("Bad input: %c", c);
        }

    } while (c != EOF);

    printf("Total Area = %d\n", area);
    printf("Ribbon Length = %d\n", ribbon);

    fclose(fp);

    return 0;
}
