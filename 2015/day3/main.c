#import <stdio.h>
#import <stdlib.h>

typedef struct {
    int x;
    int y;
} pos_t;

typedef struct {
    pos_t position;
    tree_node_t *left;
    tree_node_t *right;
} tree_node_t;

int insert_node(tree_node_t *node, pos_t pos) {

    if (node == NULL) {
        node = (tree_node_t*) malloc(sizeof(tree_node_t));
        if (node == NULL) {
            printf("malloc error\n");
            return -1;
        }
        node->position.x = pos.x;
        node->position.y = pos.y;
        node->left = NULL;
        node->right = NULL;
    }
}

tree_node_t* find_node() {

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

    tree_node_t *root = NULL;
    
    insert_node(root, current_pos);

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