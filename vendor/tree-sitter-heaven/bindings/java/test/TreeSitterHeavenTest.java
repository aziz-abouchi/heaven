import io.github.treesitter.jtreesitter.Language;
import io.github.treesitter.jtreesitter.heaven.TreeSitterHeaven;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

public class TreeSitterHeavenTest {
    @Test
    public void testCanLoadLanguage() {
        assertDoesNotThrow(() -> new Language(TreeSitterHeaven.language()));
    }
}
