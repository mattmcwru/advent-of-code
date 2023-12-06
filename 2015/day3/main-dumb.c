#import <stdio.h>

typedef struct {
    int x;
    int y;
} pos_t;

// This approach is dumb since the fixed array size is incremented until it works for the input.
// And it is slow since it does a linear search for each position.

#define POS_MAX 4096
pos_t pos_list [POS_MAX];
int pos_index = -1;

int is_new_house(pos_t p) {
    // search the list
    for (int i = 0; i <= pos_index; i++) {
        if (pos_list[i].x == p.x && pos_list[i].y == p.y)
            return 0;
    }
    return 1;
}

int add_house(pos_t p) {
    if (pos_index < POS_MAX-1) {
        pos_index++;
        pos_list[pos_index].x = p.x;
        pos_list[pos_index].y = p.y;
        return 0;
    }

    printf("Ran out of memory\n");
    return -1;
}

// Return 1 if new house, else 0
int check_house(pos_t p) {
    if (is_new_house(p)) {
        add_house(p);
        return 1;
    }
    return 0;
}

int main() {

    FILE *fp = fopen("data.txt", "r");
    if (fp == NULL) {
        printf("Error opening file\n");
        return -1;
    }

    char c;

    int house_count = 1;

    pos_t current_pos = {0, 0};

    do {
        c = fgetc(fp);

        switch(c) {
            case '>': current_pos.x++; house_count += check_house(current_pos); break;
            case '<': current_pos.x--; house_count += check_house(current_pos); break;
            case '^': current_pos.y++; house_count += check_house(current_pos); break;
            case 'v': current_pos.y--; house_count += check_house(current_pos); break;

            case '\n': 
            case EOF : break;

            default:
                printf("Bad input %c", c);
        }

    } while (c != EOF);

    printf("House count: %d\n", house_count);

    fclose(fp);
    return 0;
}